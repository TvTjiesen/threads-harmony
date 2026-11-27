export const LIBRARY_POST_LIMIT = 40;
export const LOCAL_POST_BODY_LIMIT = 500;
export const LIBRARY_REPLY_LIMIT = 80;
export const LOCAL_REPLY_BODY_LIMIT = 280;

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

export interface LibraryPost {
  id: string;
  body: string;
}

export interface LocalLibrary {
  posts: LibraryPost[];
  likedIds: string[];
  followedIds: string[];
  savedIds: string[];
  replies: LibraryReply[];
  hiddenIds: string[];
}

interface StoredLibrary extends LocalLibrary {
  version: number;
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

export function encodeLibrary(value: LocalLibrary): string {
  const stored: StoredLibrary = { version: 1, posts: value.posts, likedIds: value.likedIds,
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
  if (raw.length === 0 || raw.length > 350000) {
    return emptyLibrary();
  }
  try {
    const stored = JSON.parse(raw) as StoredLibrary;
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
      if (post !== null && typeof post === 'object' && typeof post.id === 'string' &&
        /^local-post-[1-9][0-9]{0,14}$/.test(post.id) && !ids.includes(post.id) &&
        typeof post.body === 'string' && post.body.length <= LOCAL_POST_BODY_LIMIT && post.body.trim().length > 0) {
        posts.push({ id: post.id, body: post.body });
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
