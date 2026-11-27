export const LIBRARY_POST_LIMIT = 40;
export const MAX_POST_PHOTOS = 4;
export const MAX_POST_VIDEO_DURATION_MS = 60000;
export const MAX_THREAD_PARTS = 6;
export const LOCAL_POST_BODY_LIMIT = 500;
export const LIBRARY_REPLY_LIMIT = 80;
export const LOCAL_REPLY_BODY_LIMIT = 280;

// Budget six JSON characters per body code unit and 45 per quoted photo key plus delimiter.
const STORED_PART_BUDGET = LOCAL_POST_BODY_LIMIT * 6 + MAX_POST_PHOTOS * 45 + 64;
const STORED_DRAFT_LIMIT = MAX_THREAD_PARTS * STORED_PART_BUDGET + 64;
const STORED_LIBRARY_LIMIT = LIBRARY_POST_LIMIT * STORED_DRAFT_LIMIT +
  LIBRARY_REPLY_LIMIT * (LOCAL_REPLY_BODY_LIMIT * 6 + 160) + 16384;

export interface LibraryReply {
  id: string;
  postId: string;
  body: string;
  parentId?: string;
}

export interface ReplyReference {
  id: string;
  postId: string;
}

export interface PostVideoAttachment {
  key: string;
  durationMs: number;
}

export interface ThreadPart {
  body: string;
  photoKeys?: string[];
  video?: PostVideoAttachment;
}

export interface PostDraft extends ThreadPart {
  continuation?: ThreadPart[];
}

export interface LibraryPost extends PostDraft {
  id: string;
}

interface StoredPostDraft extends PostDraft {
  photoKey?: string;
}

interface StoredLibraryPost extends StoredPostDraft {
  id: string;
}

export function isPostPhotoKey(value: string): boolean {
  return typeof value === 'string' && value.length === 42 && /^photo-[a-f0-9]{32}\.jpg$/.test(value);
}

function validPostPhotoKeys(values?: string[]): string[] {
  const keys: string[] = [];
  if (Array.isArray(values)) {
    for (const key of values) {
      if (isPostPhotoKey(key) && !keys.includes(key)) {
        keys.push(key);
        if (keys.length === MAX_POST_PHOTOS) { break; }
      }
    }
  }
  return keys;
}

function storedPostPhotoKeys(value: StoredPostDraft): string[] {
  if (Array.isArray(value.photoKeys)) {
    return validPostPhotoKeys(value.photoKeys);
  }
  const legacyKey = value.photoKey ?? '';
  return isPostPhotoKey(legacyKey) ? [legacyKey] : [];
}

export function isPostVideoKey(value: string): boolean {
  return typeof value === 'string' && value.length === 42 && /^video-[a-f0-9]{32}\.mp4$/.test(value);
}

function validPostVideo(value?: PostVideoAttachment): PostVideoAttachment | undefined {
  if (value === undefined || value === null || typeof value !== 'object' || !isPostVideoKey(value.key) ||
    !Number.isInteger(value.durationMs) || value.durationMs <= 0 || value.durationMs > MAX_POST_VIDEO_DURATION_MS) {
    return undefined;
  }
  return { key: value.key, durationMs: value.durationMs };
}

function draftWithMedia(body: string, photoKeys: string[], video?: PostVideoAttachment): PostDraft {
  if (photoKeys.length > 0) { return { body: body, photoKeys: photoKeys }; }
  return video === undefined ? { body: body } : { body: body, video: video };
}

function copyContinuation(continuation: ThreadPart[]): ThreadPart[] {
  return continuation.map((part: ThreadPart): ThreadPart =>
    draftWithMedia(part.body, part.photoKeys?.slice() ?? [], validPostVideo(part.video)));
}

function postWithMedia(id: string, body: string, photoKeys: string[], video?: PostVideoAttachment,
  continuation?: ThreadPart[]): LibraryPost {
  const post: LibraryPost = { id: id, body: body };
  if (photoKeys.length > 0) {
    post.photoKeys = photoKeys;
  } else if (video !== undefined) {
    post.video = video;
  }
  if (continuation !== undefined) { post.continuation = copyContinuation(continuation); }
  return post;
}

export function canKeepPost(body: string, photoKeys: string[], video?: PostVideoAttachment): boolean {
  return body.length <= LOCAL_POST_BODY_LIMIT &&
    (body.trim().length > 0 || photoKeys.some(isPostPhotoKey) || validPostVideo(video) !== undefined);
}

function validThreadPart(part: ThreadPart): boolean {
  if (part === undefined || part === null || typeof part !== 'object' || Array.isArray(part) ||
    typeof part.body !== 'string' || part.body.length > LOCAL_POST_BODY_LIMIT) { return false; }
  const keys = part.photoKeys;
  if (keys !== undefined && (!Array.isArray(keys) || keys.length > MAX_POST_PHOTOS ||
    validPostPhotoKeys(keys).length !== keys.length)) { return false; }
  return part.video === undefined || ((keys?.length ?? 0) === 0 && !Array.isArray(part.video) &&
    validPostVideo(part.video) !== undefined);
}

function validContinuation(continuation: ThreadPart[], allowBlank: boolean): boolean {
  if (!Array.isArray(continuation) || continuation.length >= MAX_THREAD_PARTS) { return false; }
  for (const part of continuation) {
    if (!validThreadPart(part)) { return false; }
    const storedPart = part as StoredPostDraft;
    if (storedPart.continuation !== undefined || storedPart.photoKey !== undefined ||
      (!allowBlank && !canKeepPost(part.body, part.photoKeys ?? [], part.video))) { return false; }
  }
  return true;
}

export function canPublishThread(part: ThreadPart, continuation: ThreadPart[]): boolean {
  return validThreadPart(part) && canKeepPost(part.body, part.photoKeys ?? [], part.video) &&
    validContinuation(continuation, false);
}

export function decodePostDraft(raw: string): PostDraft {
  if (raw.length > STORED_DRAFT_LIMIT) { throw new Error('Invalid local draft'); }
  const value = JSON.parse(raw) as StoredPostDraft;
  if (value === null || typeof value !== 'object' || typeof value.body !== 'string' ||
    value.body.length > LOCAL_POST_BODY_LIMIT) { throw new Error('Invalid local draft'); }
  const continuation = value.continuation;
  if (continuation !== undefined && !validContinuation(continuation, true)) { throw new Error('Invalid local draft'); }
  const draft = draftWithMedia(value.body, storedPostPhotoKeys(value), validPostVideo(value.video));
  if (continuation !== undefined) { draft.continuation = copyContinuation(continuation); }
  return draft;
}

interface LibraryState {
  likedIds: string[];
  followedIds: string[];
  savedIds: string[];
  replies: LibraryReply[];
  hiddenIds: string[];
}

export interface LocalLibrary extends LibraryState {
  posts: LibraryPost[];
}

interface StoredLibrary<T> extends LibraryState {
  version: number;
  posts: T[];
}

export interface LibraryPatch {
  posts?: LibraryPost[];
  likedIds?: string[];
  followedIds?: string[];
  savedIds?: string[];
  replies?: LibraryReply[];
  hiddenIds?: string[];
}

export function updateLibrary(value: LocalLibrary, patch: LibraryPatch): LocalLibrary {
  return { posts: patch.posts ?? value.posts, likedIds: patch.likedIds ?? value.likedIds,
    followedIds: patch.followedIds ?? value.followedIds, savedIds: patch.savedIds ?? value.savedIds,
    replies: patch.replies ?? value.replies, hiddenIds: patch.hiddenIds ?? value.hiddenIds };
}

function canStoreContinuation(post: PostDraft): boolean {
  const continuation = post.continuation;
  // Only pre-thread posts may be restored by dropping invalid or conflicting legacy media.
  return continuation === undefined || ((post as StoredPostDraft).photoKey === undefined &&
    canPublishThread(post, continuation));
}

export function encodeLibrary(value: LocalLibrary): string {
  const posts: LibraryPost[] = [];
  for (const post of value.posts) {
    if (!canStoreContinuation(post)) { continue; }
    posts.push(postWithMedia(post.id, post.body, validPostPhotoKeys(post.photoKeys), validPostVideo(post.video),
      post.continuation));
  }
  const stored: StoredLibrary<LibraryPost> = { version: 1, posts: posts, likedIds: value.likedIds,
    followedIds: value.followedIds, savedIds: value.savedIds, replies: value.replies, hiddenIds: value.hiddenIds };
  return JSON.stringify(stored);
}

export function emptyLibrary(): LocalLibrary {
  return { posts: [], likedIds: [], followedIds: [], savedIds: [], replies: [], hiddenIds: [] };
}

function validIds(values: string[], allowed: string[]): string[] {
  const result: string[] = [];
  if (Array.isArray(values)) {
    for (const id of values) {
      if (typeof id === 'string' && allowed.includes(id) && !result.includes(id)) {
        result.push(id);
      }
    }
  }
  return result;
}

function validReplies(values: LibraryReply[], postIds: string[], samples: ReplyReference[]): LibraryReply[] {
  const candidates: LibraryReply[] = [];
  const byId = new Map<string, LibraryReply>();
  for (const row of values) {
    if (candidates.length >= LIBRARY_REPLY_LIMIT) { break; }
    if (row === null || typeof row !== 'object' || typeof row.id !== 'string' ||
      !/^local-[1-9][0-9]{0,14}$/.test(row.id) || byId.has(row.id) || !postIds.includes(row.postId) ||
      typeof row.body !== 'string' || !row.body.trim() || row.body.length > LOCAL_REPLY_BODY_LIMIT ||
      (row.parentId !== undefined && typeof row.parentId !== 'string')) { continue; }
    const reply: LibraryReply = { id: row.id, postId: row.postId, body: row.body, parentId: row.parentId };
    candidates.push(reply);
    byId.set(reply.id, reply);
  }
  return candidates.filter((reply: LibraryReply) => {
    let parent = reply.parentId;
    const seen: string[] = [reply.id];
    while (parent !== undefined) {
      if (seen.includes(parent)) { return false; }
      seen.push(parent);
      const parentReply = byId.get(parent);
      if (parentReply === undefined) {
        return samples.some((sample: ReplyReference) => sample.id === parent && sample.postId === reply.postId);
      }
      if (parentReply.postId !== reply.postId) { return false; }
      parent = parentReply.parentId;
    }
    return true;
  });
}

export function decodeLibrary(raw: string, demoIds: string[], samples: ReplyReference[] = []): LocalLibrary {
  if (raw.length === 0 || raw.length > STORED_LIBRARY_LIMIT) {
    return emptyLibrary();
  }
  try {
    const stored = JSON.parse(raw) as StoredLibrary<StoredLibraryPost>;
    if (stored === null || typeof stored !== 'object' || stored.version !== 1 || !Array.isArray(stored.posts) ||
      !Array.isArray(stored.likedIds) || !Array.isArray(stored.followedIds) || !Array.isArray(stored.savedIds)) {
      return emptyLibrary();
    }
    const posts: LibraryPost[] = [];
    const ids = [...demoIds];
    for (const post of stored.posts) {
      if (posts.length >= LIBRARY_POST_LIMIT) {
        break;
      }
      if (post === null || typeof post !== 'object' || typeof post.id !== 'string' ||
        !/^local-post-[1-9][0-9]{0,14}$/.test(post.id) || ids.includes(post.id) || typeof post.body !== 'string') {
        continue;
      }
      if (!canStoreContinuation(post)) { continue; }
      const keys = storedPostPhotoKeys(post);
      const video = validPostVideo(post.video);
      if (canKeepPost(post.body, keys, video)) {
        posts.push(postWithMedia(post.id, post.body, keys, video, post.continuation));
        ids.push(post.id);
      }
    }
    return {
      posts: posts,
      likedIds: validIds(stored.likedIds, ids),
      followedIds: validIds(stored.followedIds, demoIds),
      savedIds: validIds(stored.savedIds, ids),
      replies: validReplies(Array.isArray(stored.replies) ? stored.replies : [], ids, samples),
      hiddenIds: validIds(stored.hiddenIds, demoIds)
    };
  } catch (_error) {
    return emptyLibrary();
  }
}

export function matchesPost(query: string, name: string, handle: string, body: string): boolean {
  const value = query.trim().toLowerCase();
  if (value.length === 0) {
    return true;
  }
  const source = `${name}\n${handle}\n${body}`.toLowerCase();
  return value.split(/\s+/).every((term: string) => source.includes(term));
}
