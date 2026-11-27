import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { media } from '@kit.MediaKit';
import { isPostVideoKey, MAX_POST_VIDEO_DURATION_MS, PostVideoAttachment } from './LocalLibrary';

const VIDEO_FOLDER = 'post-videos';
const MAX_VIDEO_BYTES = 64 * 1024 * 1024;
const MAX_VIDEO_SIDE = 4096;
const MAX_VIDEO_PIXELS = 4096 * 2160;
const COPY_CHUNK_BYTES = 256 * 1024;
const MAX_POSTER_SIDE = 720;
const MAX_POSTER_BYTES = 2 * 1024 * 1024;
const METADATA_TIMEOUT_MS = 5000;
const POSTER_TIMEOUT_MS = 4000;
const FILE_NOT_FOUND = 13900002;
const UNREADABLE_VIDEO = '无法读取所选视频，请重新选择已保存在本机的视频。';
const UNSUPPORTED_VIDEO = '只能导入有效的 MP4 视频，请重新选择。';
const SAVE_FAILED = '无法将视频保存到本机，请检查存储空间后重试。';

function videoFolder(context: common.UIAbilityContext): string {
  return `${context.filesDir}/${VIDEO_FOLDER}`;
}

function videoPosterPath(videoPath: string): string {
  return `${videoPath.slice(0, -4)}.jpg`;
}

function isDirectory(path: string): boolean {
  try {
    return fileIo.lstatSync(path).isDirectory();
  } catch (_error) {
    return false;
  }
}

function isRegularFile(path: string): boolean {
  try {
    return fileIo.lstatSync(path).isFile();
  } catch (_error) {
    return false;
  }
}

function isMissing(path: string): boolean {
  try {
    fileIo.lstatSync(path);
    return false;
  } catch (error) {
    return (error as BusinessError).code === FILE_NOT_FOUND;
  }
}

function unlinkPrivateFile(path: string): void {
  if (isRegularFile(path)) {
    try {
      fileIo.unlinkSync(path);
    } catch (_error) {
      // Cleanup is best effort if storage is no longer writable.
    }
  }
}

function openNewPrivateFile(path: string): fileIo.File {
  if (!isMissing(path)) {
    throw new Error(SAVE_FAILED);
  }
  return fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.NOFOLLOW);
}

async function selectVideo(): Promise<string | undefined> {
  const options = new photoAccessHelper.PhotoSelectOptions();
  options.maxSelectNumber = 1;
  options.isPhotoTakingSupported = false;
  options.isEditSupported = false;
  // assetFilter replaces MIME filtering; include the video type and require a local copy.
  options.assetFilter = [
    { operationType: photoAccessHelper.OperationType.BEGIN_WRAP },
    {
      operationType: photoAccessHelper.OperationType.EQUAL_TO,
      field: photoAccessHelper.PhotoKeys.PHOTO_TYPE,
      value: [photoAccessHelper.PhotoType.VIDEO]
    },
    { operationType: photoAccessHelper.OperationType.AND },
    {
      operationType: photoAccessHelper.OperationType.IN,
      field: photoAccessHelper.PhotoKeys.POSITION,
      value: [photoAccessHelper.PositionType.LOCAL, photoAccessHelper.PositionType.LOCAL_AND_CLOUD]
    },
    { operationType: photoAccessHelper.OperationType.END_WRAP }
  ];
  let result: photoAccessHelper.PhotoSelectResult;
  try {
    result = await new photoAccessHelper.PhotoViewPicker().select(options);
  } catch (_error) {
    throw new Error('无法打开系统相册，请重试。');
  }
  if (result.photoUris.length === 0) {
    return undefined;
  }
  const uri = result.photoUris[0];
  if (result.photoUris.length !== 1 || typeof uri !== 'string' ||
    !uri.startsWith('file://media/Photo/') || uri.length <= 'file://media/Photo/'.length) {
    throw new Error('只能从系统相册选择一个已保存在本机的视频。');
  }
  return uri;
}

function fourCc(bytes: DataView, offset: number): string {
  return String.fromCharCode(bytes.getUint8(offset), bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2), bytes.getUint8(offset + 3));
}

async function readMp4Header(fd: number, size: number): Promise<ArrayBuffer> {
  const header = new ArrayBuffer(16);
  if (size <= header.byteLength) {
    throw new Error(UNSUPPORTED_VIDEO);
  }
  let total = 0;
  while (total < header.byteLength) {
    const chunk = new ArrayBuffer(header.byteLength - total);
    let read: number;
    try {
      read = await fileIo.read(fd, chunk);
    } catch (_error) {
      throw new Error(UNREADABLE_VIDEO);
    }
    if (read <= 0 || read > chunk.byteLength) {
      throw new Error(UNREADABLE_VIDEO);
    }
    new Uint8Array(header).set(new Uint8Array(chunk, 0, read), total);
    total += read;
  }
  const bytes = new DataView(header);
  const boxSize = bytes.getUint32(0);
  const brand = fourCc(bytes, 8);
  // Do not let a generic ISO BMFF signature relabel MOV, 3GP or HEIF as an MP4.
  if (fourCc(bytes, 4) !== 'ftyp' || boxSize < 16 || boxSize >= size || boxSize % 4 !== 0 ||
    !/^(isom|iso[2-9]|mp41|mp42|avc1|hvc1|hev1|M4V |MSNV|dash)$/.test(brand)) {
    throw new Error(UNSUPPORTED_VIDEO);
  }
  return header;
}

async function copySelectedVideo(uri: string, folder: string, path: string): Promise<number> {
  let source: fileIo.File | undefined;
  let destination: fileIo.File | undefined;
  let created = false;
  let completed = false;
  let message = UNREADABLE_VIDEO;
  try {
    source = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    if (!Number.isSafeInteger(source.fd) || source.fd < 0) {
      throw new Error();
    }
    const stat = await fileIo.stat(source.fd);
    const size = stat.size;
    if (!stat.isFile() || !Number.isSafeInteger(size) || size <= 0) {
      throw new Error();
    }
    if (size > MAX_VIDEO_BYTES) {
      message = '视频超过 64 MiB，请选择较小的视频。';
      throw new Error();
    }
    message = '';
    const header = await readMp4Header(source.fd, size);
    message = SAVE_FAILED;
    if (!isDirectory(folder)) {
      fileIo.mkdirSync(folder);
    }
    if (!isDirectory(folder) || !isMissing(videoPosterPath(path))) {
      throw new Error();
    }
    destination = openNewPrivateFile(path);
    created = true;
    if (await fileIo.write(destination.fd, header) !== header.byteLength) {
      throw new Error();
    }
    const buffer = new ArrayBuffer(Math.min(size - header.byteLength, COPY_CHUNK_BYTES));
    let copied = header.byteLength;
    while (copied < size) {
      message = UNREADABLE_VIDEO;
      const length = Math.min(buffer.byteLength, size - copied);
      const read = await fileIo.read(source.fd, buffer, { length: length });
      if (read <= 0 || read > length) {
        throw new Error();
      }
      message = SAVE_FAILED;
      if (await fileIo.write(destination.fd, buffer, { length: read }) !== read) {
        throw new Error();
      }
      copied += read;
    }
    message = UNREADABLE_VIDEO;
    if (await fileIo.read(source.fd, buffer, { length: 1 }) !== 0) {
      throw new Error();
    }
    message = SAVE_FAILED;
    await fileIo.fsync(destination.fd);
    await fileIo.close(destination);
    destination = undefined;
    completed = true;
    return size;
  } catch (error) {
    throw new Error(message || (error instanceof Error ? error.message : UNREADABLE_VIDEO));
  } finally {
    if (destination !== undefined) {
      await closeQuietly(destination);
    }
    if (created && !completed && isDirectory(folder)) {
      unlinkPrivateFile(path);
    }
    if (source !== undefined) {
      await closeQuietly(source);
    }
  }
}

async function closeQuietly(file: fileIo.File): Promise<void> {
  try {
    await fileIo.close(file);
  } catch (_error) {
    // Do not mask the original failure with a close error.
  }
}

async function savePoster(path: string, pixels: image.PixelMap): Promise<void> {
  let packer: image.ImagePacker | undefined;
  let file: fileIo.File | undefined;
  let created = false;
  let completed = false;
  try {
    packer = image.createImagePacker();
    const jpeg = await packer.packToData(pixels, {
      format: 'image/jpeg', quality: 82, bufferSize: MAX_POSTER_BYTES, needsPackProperties: false
    });
    if (jpeg.byteLength <= 0 || jpeg.byteLength > MAX_POSTER_BYTES) {
      return;
    }
    file = openNewPrivateFile(path);
    created = true;
    if (await fileIo.write(file.fd, jpeg) !== jpeg.byteLength) {
      return;
    }
    await fileIo.fsync(file.fd);
    await fileIo.close(file);
    file = undefined;
    completed = true;
  } finally {
    try {
      if (file !== undefined) {
        await closeQuietly(file);
      }
      if (created && !completed) {
        unlinkPrivateFile(path);
      }
    } finally {
      try {
        await packer?.release();
      } catch (_error) {
        // Poster packing is optional.
      }
    }
  }
}

async function tryMakePoster(extractor: media.AVMetadataExtractor, path: string, width: number,
  height: number): Promise<void> {
  let pixels: image.PixelMap | undefined;
  try {
    const scale = Math.min(1, MAX_POSTER_SIDE / Math.max(width, height));
    pixels = await extractor.fetchFrameByTimeWithTimeout(0, media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC, {
      width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale))
    }, POSTER_TIMEOUT_MS);
    if (pixels === undefined) {
      return;
    }
    const info = await pixels.getImageInfo();
    const side = Math.max(info.size.width, info.size.height);
    if (side > MAX_POSTER_SIDE) {
      await pixels.scale(MAX_POSTER_SIDE / side, MAX_POSTER_SIDE / side);
    }
    await savePoster(path, pixels);
  } catch (_error) {
    // Some devices/codecs cannot extract a thumbnail; a valid video still imports.
  } finally {
    try {
      await pixels?.release();
    } catch (_error) {
      // Still release the extractor and its file descriptor.
    }
  }
}

async function inspectSavedVideo(path: string, size: number): Promise<number> {
  let extractor: media.AVMetadataExtractor | undefined;
  let file: fileIo.File | undefined;
  let message = UNSUPPORTED_VIDEO;
  try {
    // Inspect the exact private snapshot that will be played, not the mutable picker source.
    file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.NOFOLLOW);
    extractor = await media.createAVMetadataExtractor();
    extractor.fdSrc = { fd: file.fd, offset: 0, length: size };
    const metadata = await extractor.fetchMetadataWithTimeout(METADATA_TIMEOUT_MS);
    if (metadata === undefined || metadata.mimeType !== 'video/mp4') {
      throw new Error();
    }
    const durationMs = Number(metadata.duration);
    const width = Number(metadata.videoWidth);
    const height = Number(metadata.videoHeight);
    if (!Number.isSafeInteger(durationMs) || durationMs <= 0 ||
      !Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width <= 0 || height <= 0) {
      throw new Error();
    }
    if (durationMs > MAX_POST_VIDEO_DURATION_MS) {
      message = '视频超过 60 秒，请选择较短的视频。';
      throw new Error();
    }
    if (width > MAX_VIDEO_SIDE || height > MAX_VIDEO_SIDE || width * height > MAX_VIDEO_PIXELS) {
      message = '视频分辨率过高，请选择边长不超过 4096 像素、总像素不超过 4096×2160 的视频。';
      throw new Error();
    }
    await tryMakePoster(extractor, videoPosterPath(path), width, height);
    return durationMs;
  } catch (_error) {
    throw new Error(message);
  } finally {
    try {
      await extractor?.release();
    } catch (_error) {
      // The private descriptor still needs to be closed.
    } finally {
      if (file !== undefined) {
        await closeQuietly(file);
      }
    }
  }
}

async function selectVideoFile(context: common.UIAbilityContext): Promise<string | undefined> {
  const options = new picker.DocumentSelectOptions();
  options.maxSelectNumber = 1;
  options.fileSuffixFilters = ['MP4 视频|.mp4'];
  let uris: string[];
  try {
    uris = await new picker.DocumentViewPicker(context).select(options);
  } catch (_error) {
    throw new Error('无法打开系统文件选择器，请重试。');
  }
  if (uris.length === 0) { return undefined; }
  if (uris.length !== 1 || !uris[0].startsWith('file://')) {
    throw new Error('请选择一个本机 MP4 文件。');
  }
  return uris[0];
}

export async function pickPostVideo(context: common.UIAbilityContext, fromFiles: boolean = false): Promise<PostVideoAttachment | undefined> {
  const uri = fromFiles ? await selectVideoFile(context) : await selectVideo();
  if (uri === undefined) {
    return undefined;
  }
  const folder = videoFolder(context);
  const key = `video-${util.generateRandomUUID().replace(/-/g, '').toLowerCase()}.mp4`;
  if (!isPostVideoKey(key)) {
    throw new Error(SAVE_FAILED);
  }
  const path = `${folder}/${key}`;
  const size = await copySelectedVideo(uri, folder, path);
  try {
    const durationMs = await inspectSavedVideo(path, size);
    return { key: key, durationMs: durationMs };
  } catch (error) {
    discardPostVideo(context, key);
    throw new Error(error instanceof Error ? error.message : UNSUPPORTED_VIDEO);
  }
}

function privateFileUri(folder: string, path: string): string {
  if (!isDirectory(folder) || !isRegularFile(path)) {
    return '';
  }
  try {
    return fileUri.getUriFromPath(path);
  } catch (_error) {
    return '';
  }
}

export function postVideoUri(context: common.UIAbilityContext, key: string): string {
  if (!isPostVideoKey(key)) {
    return '';
  }
  const folder = videoFolder(context);
  return privateFileUri(folder, `${folder}/${key}`);
}

export function postVideoPosterUri(context: common.UIAbilityContext, key: string): string {
  if (!isPostVideoKey(key)) {
    return '';
  }
  const folder = videoFolder(context);
  return privateFileUri(folder, videoPosterPath(`${folder}/${key}`));
}

export function discardPostVideo(context: common.UIAbilityContext, key: string): void {
  if (!isPostVideoKey(key)) {
    return;
  }
  const folder = videoFolder(context);
  if (isDirectory(folder)) {
    const path = `${folder}/${key}`;
    unlinkPrivateFile(path);
    unlinkPrivateFile(videoPosterPath(path));
  }
}
