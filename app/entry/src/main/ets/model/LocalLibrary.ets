export const LIBRARY_POST_LIMIT = 40;
export const LOCAL_POST_BODY_LIMIT = 500;

export interface LibraryPost {
  id: string;
  body: string;
}

export interface LocalLibrary {
  posts: LibraryPost[];
  likedIds: string[];
  followedIds: string[];
  savedIds: string[];
}

interface StoredLibrary extends LocalLibrary {
  version: number;
}

export function emptyLibrary(): LocalLibrary {
  return { posts: [], likedIds: [], followedIds: [], savedIds: [] };
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

export function decodeLibrary(raw: string, demoIds: string[]): LocalLibrary {
  if (raw.length === 0 || raw.length > 150000) {
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
      savedIds: validIds(stored.savedIds, ids)
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
