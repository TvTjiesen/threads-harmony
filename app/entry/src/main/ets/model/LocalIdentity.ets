export const IDENTITY_NAME_LIMIT = 24;
export const IDENTITY_BIO_LIMIT = 160;
const IDENTITY_SNAPSHOT_LIMIT = 4096;

export interface LocalIdentity {
  name: string;
  bio: string;
}

export function emptyIdentity(): LocalIdentity {
  return { name: '你', bio: '' };
}

export function identityLength(value: string): number {
  let length = 0;
  for (let index = 0; index < value.length; index++) {
    const point = value.codePointAt(index);
    if (point === undefined || (point >= 0xD800 && point <= 0xDFFF)) {
      return -1;
    }
    if (point > 0xFFFF) {
      index++;
    }
    length++;
  }
  return length;
}

export function normalizeIdentity(name: string, bio: string): LocalIdentity | undefined {
  const cleanName = name.trim();
  const cleanBio = bio.replace(/\r\n?|[\u2028\u2029]/g, '\n').trim();
  const nameLength = identityLength(cleanName);
  const bioLength = identityLength(cleanBio);
  if (nameLength < 1 || nameLength > IDENTITY_NAME_LIMIT || bioLength < 0 || bioLength > IDENTITY_BIO_LIMIT ||
    /[\x00-\x1F\x7F-\x9F\u2028\u2029]/.test(cleanName) || /[\x00-\x09\x0B-\x1F\x7F-\x9F]/.test(cleanBio)) {
    return undefined;
  }
  return { name: cleanName, bio: cleanBio };
}

export function decodeIdentity(raw: string): LocalIdentity {
  if (raw.length === 0 || raw.length > IDENTITY_SNAPSHOT_LIMIT) {
    return emptyIdentity();
  }
  try {
    const stored = JSON.parse(raw) as LocalIdentity;
    if (stored === null || typeof stored !== 'object' || typeof stored.name !== 'string' ||
      typeof stored.bio !== 'string') {
      return emptyIdentity();
    }
    return normalizeIdentity(stored.name, stored.bio) ?? emptyIdentity();
  } catch (_error) {
    return emptyIdentity();
  }
}
