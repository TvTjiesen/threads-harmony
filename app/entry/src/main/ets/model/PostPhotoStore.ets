import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { isPostPhotoKey, MAX_POST_PHOTOS } from './LocalLibrary';

const PHOTO_FOLDER = 'post-photos';
const MAX_SOURCE_BYTES = 20 * 1024 * 1024;
const MAX_SOURCE_PIXELS = 24_000_000;
const MAX_SOURCE_SIDE = 8192;
const MAX_OUTPUT_SIDE = 2048;
const MAX_OUTPUT_BYTES = 6 * 1024 * 1024;
const FILE_NOT_FOUND = 13900002;

function photoFolder(context: common.UIAbilityContext): string {
  return `${context.filesDir}/${PHOTO_FOLDER}`;
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

async function selectPhotos(maxCount: number): Promise<string[]> {
  const options = new photoAccessHelper.PhotoSelectOptions();
  options.maxSelectNumber = maxCount;
  options.isPhotoTakingSupported = false;
  options.isEditSupported = false;
  // assetFilter replaces the MIME filter: require an image with bytes already on this device.
  options.assetFilter = [
    {
      operationType: photoAccessHelper.OperationType.EQUAL_TO,
      field: photoAccessHelper.PhotoKeys.PHOTO_TYPE,
      value: [photoAccessHelper.PhotoType.IMAGE]
    },
    { operationType: photoAccessHelper.OperationType.AND },
    {
      operationType: photoAccessHelper.OperationType.IN,
      field: photoAccessHelper.PhotoKeys.POSITION,
      value: [photoAccessHelper.PositionType.LOCAL, photoAccessHelper.PositionType.LOCAL_AND_CLOUD]
    }
  ];
  let result: photoAccessHelper.PhotoSelectResult;
  try {
    result = await new photoAccessHelper.PhotoViewPicker().select(options);
  } catch (_error) {
    throw new Error('无法打开系统相册，请重试。');
  }
  if (result.photoUris.length > maxCount || result.photoUris.some((uri: string) =>
    typeof uri !== 'string' || !uri.startsWith('file://media/Photo/'))) {
    throw new Error(`只能从系统相册选择最多 ${maxCount} 张本机照片。`);
  }
  return result.photoUris;
}

async function readSelectedPhoto(uri: string): Promise<ArrayBuffer> {
  let message = '无法读取所选照片，请重新选择已保存在本机的照片。';
  try {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = await fileIo.stat(file.fd);
      if (!stat.isFile() || !Number.isInteger(stat.size) || stat.size <= 0) {
        throw new Error(message);
      }
      const size = stat.size;
      if (size > MAX_SOURCE_BYTES) {
        message = '照片超过 20 MiB，请选择较小的照片。';
        throw new Error(message);
      }
      // Decode a bounded snapshot, not a URI or descriptor that could change after validation.
      const data = new ArrayBuffer(size);
      const output = new Uint8Array(data);
      const chunk = new ArrayBuffer(Math.min(size, 256 * 1024));
      const bytes = new Uint8Array(chunk);
      let offset = 0;
      while (offset < size) {
        const length = Math.min(chunk.byteLength, size - offset);
        const read = await fileIo.read(file.fd, chunk, { length: length });
        if (read <= 0 || read > length) {
          throw new Error(message);
        }
        output.set(bytes.subarray(0, read), offset);
        offset += read;
      }
      if (await fileIo.read(file.fd, chunk, { length: 1 }) !== 0) {
        throw new Error(message);
      }
      return data;
    } finally {
      await fileIo.close(file);
    }
  } catch (_error) {
    throw new Error(message);
  }
}

async function normalizePhoto(data: ArrayBuffer): Promise<ArrayBuffer> {
  let message = '无法读取照片，请选择有效的 JPEG、PNG、HEIF 或 WebP 图片。';
  let source: image.ImageSource | undefined;
  let pixels: image.PixelMap | undefined;
  let packer: image.ImagePacker | undefined;
  try {
    source = image.createImageSource(data);
    const info = await source.getImageInfo();
    if (info.mimeType !== 'image/jpeg' && info.mimeType !== 'image/png' &&
      info.mimeType !== 'image/heic' && info.mimeType !== 'image/heif' && info.mimeType !== 'image/webp') {
      throw new Error(message);
    }
    const width = info.size.width;
    const height = info.size.height;
    if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0) {
      throw new Error(message);
    }
    if (width > MAX_SOURCE_SIDE || height > MAX_SOURCE_SIDE || width * height > MAX_SOURCE_PIXELS) {
      message = '照片分辨率过高，请选择不超过 2400 万像素、且边长不超过 8192 像素的照片。';
      throw new Error(message);
    }
    if (await source.getFrameCount() !== 1) {
      message = '不支持多帧图片，请选择静态照片。';
      throw new Error(message);
    }
    message = '无法解码这张照片，请换一张照片。';
    const scale = Math.min(1, MAX_OUTPUT_SIDE / Math.max(width, height));
    pixels = await source.createPixelMap({
      desiredSize: { width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) },
      desiredDynamicRange: image.DecodingDynamicRange.SDR
    });
    message = '无法将照片转换为 JPEG，请换一张较小的照片。';
    packer = image.createImagePacker();
    const jpeg = await packer.packToData(pixels, {
      format: 'image/jpeg', quality: 85, bufferSize: MAX_OUTPUT_BYTES, needsPackProperties: false,
      backgroundColor: 0xFFFFFF
    });
    if (jpeg.byteLength === 0 || jpeg.byteLength > MAX_OUTPUT_BYTES) {
      throw new Error(message);
    }
    return jpeg;
  } catch (_error) {
    throw new Error(message);
  } finally {
    await packer?.release().catch(() => {});
    await pixels?.release().catch(() => {});
    await source?.release().catch(() => {});
  }
}

function unlinkPhoto(path: string): void {
  if (isRegularFile(path)) {
    try {
      fileIo.unlinkSync(path);
    } catch (_error) {
      // Cleanup is best-effort; a later prune can retry.
    }
  }
}

async function savePhoto(context: common.UIAbilityContext, jpeg: ArrayBuffer): Promise<string> {
  const folder = photoFolder(context);
  let opened = false;
  let path = '';
  try {
    if (!isDirectory(folder)) {
      fileIo.mkdirSync(folder);
      if (!isDirectory(folder)) {
        throw new Error();
      }
    }
    const key = `photo-${util.generateRandomUUID().replace(/-/g, '').toLowerCase()}.jpg`;
    if (!isPostPhotoKey(key)) {
      throw new Error();
    }
    path = `${folder}/${key}`;
    if (!isMissing(path)) {
      throw new Error();
    }
    const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.NOFOLLOW);
    opened = true;
    try {
      if (await fileIo.write(file.fd, jpeg) !== jpeg.byteLength) {
        throw new Error();
      }
      await fileIo.fsync(file.fd);
    } finally {
      await fileIo.close(file);
    }
    return key;
  } catch (_error) {
    if (opened && isDirectory(folder)) {
      unlinkPhoto(path);
    }
    throw new Error('无法将照片保存到本机，请检查存储空间后重试。');
  }
}

export async function pickPostPhotos(context: common.UIAbilityContext, maxCount: number): Promise<string[]> {
  const limit = Math.min(MAX_POST_PHOTOS, Math.floor(maxCount));
  if (!(limit > 0)) {
    return [];
  }
  const uris = await selectPhotos(limit);
  const keys: string[] = [];
  try {
    for (const uri of uris) {
      const jpeg = await normalizePhoto(await readSelectedPhoto(uri));
      keys.push(await savePhoto(context, jpeg));
    }
    return keys;
  } catch (error) {
    for (const key of keys) {
      discardPostPhoto(context, key);
    }
    throw new Error(error instanceof Error ? error.message : '无法导入所选照片，请重试。');
  }
}

export function postPhotoUri(context: common.UIAbilityContext, key: string): string {
  if (!isPostPhotoKey(key)) {
    return '';
  }
  const folder = photoFolder(context);
  const path = `${folder}/${key}`;
  if (!isDirectory(folder) || !isRegularFile(path)) {
    return '';
  }
  try {
    return fileUri.getUriFromPath(path);
  } catch (_error) {
    return '';
  }
}

export function discardPostPhoto(context: common.UIAbilityContext, key: string): void {
  if (!isPostPhotoKey(key)) {
    return;
  }
  const folder = photoFolder(context);
  if (isDirectory(folder)) {
    unlinkPhoto(`${folder}/${key}`);
  }
}

export function prunePostPhotos(context: common.UIAbilityContext, retained: string[]): void {
  const folder = photoFolder(context);
  if (!isDirectory(folder)) {
    return;
  }
  const keep = new Set<string>(retained);
  try {
    for (const name of fileIo.listFileSync(folder)) {
      if (isPostPhotoKey(name) && !keep.has(name)) {
        unlinkPhoto(`${folder}/${name}`);
      }
    }
  } catch (_error) {
    // A failed listing is not permission to delete anything.
  }
}
