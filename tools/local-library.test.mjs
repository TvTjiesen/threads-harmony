import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const source = readFileSync(new URL('../app/entry/src/main/ets/model/LocalLibrary.ets', import.meta.url), 'utf8');
const modelUrl = `data:text/javascript,${encodeURIComponent(stripTypeScriptTypes(source))}`;
const { canKeepPost, decodeLibrary, decodePostDraft, emptyLibrary, encodeLibrary, isPostPhotoKey, matchesPost } = await import(modelUrl);

const demoIds = ['p1', 'p2'];
const legacy = { posts: [], likedIds: [], followedIds: [], savedIds: [] };
const empty = { ...legacy, replies: [], hiddenIds: [] };
const persisted = (fields = {}) => JSON.stringify({ version: 1, ...legacy, ...fields });

test('an older snapshot restores existing content and defaults the new fields', () => {
  assert.deepEqual(emptyLibrary(), empty);
  const state = {
    posts: [{ id: 'local-post-1', body: '  我自己的帖子\n' }],
    likedIds: ['local-post-1', 'p1'],
    followedIds: ['p1'],
    savedIds: ['p2', 'local-post-1']
  };
  const restored = decodeLibrary(persisted(state), demoIds);
  assert.deepEqual(restored, { ...state, replies: [], hiddenIds: [] });
  assert.deepEqual(decodeLibrary(persisted(restored), demoIds), restored);
});

test('reply restoration keeps only valid same-post chains and hides demo posts only', () => {
  const reply = (id, postId, parentId, body = 'valid') => ({ id: `local-${id}`, postId, parentId, body });
  const first = reply(1, 'p1', 'sample-1');
  const second = reply(2, 'p1', first.id, '  preserving reply text  ');
  const state = decodeLibrary(persisted({
    posts: [{ id: 'local-post-1', body: 'Local post' }],
    hiddenIds: ['p2', 'p2', 'other', 'local-post-1'],
    replies: [second, first, reply(1, 'p1', undefined, 'duplicate'), reply(3, 'p2', first.id),
      reply(4, 'p1', 'local-5'), reply(5, 'p1', 'local-4'), reply(6, 'p1', 'missing'),
      reply(7, 'p2', 'sample-1'), reply(8, 'missing-post'), reply(9, 'p1', undefined, ' '),
      reply(10, 'p1', 'local-6'), reply(11, 'p1', undefined, '🙂'.repeat(141))]
  }), demoIds, [{ id: 'sample-1', postId: 'p1' }]);
  assert.deepEqual(state.replies, [second, first]);
  assert.deepEqual(state.hiddenIds, ['p2']);
});

test('no more than 80 replies survive restoration', () => {
  const replies = Array.from({ length: 81 }, (_, i) => ({ id: `local-${i + 1}`, postId: 'p1', body: `Reply ${i}` }));
  assert.equal(decodeLibrary(persisted({ replies }), demoIds).replies.length, 80);
});

test('missing, corrupted, or incompatible snapshots fall back to an empty library', () => {
  const post = { id: 'local-post-1', body: 'valid post' };
  const cases = [
    '',
    '{"version":1,',
    'null',
    '[]',
    '42',
    JSON.stringify({ ...empty, posts: [post] }),
    persisted({ version: 2, posts: [post] }),
    persisted({ version: '1', posts: [post] }),
    persisted({ posts: null, likedIds: ['p1'] }),
    persisted({ posts: [post], likedIds: 'p1' }),
    persisted({ posts: [post], followedIds: undefined }),
    persisted({ posts: [post], savedIds: {} })
  ];
  for (const raw of cases) {
    assert.deepEqual(decodeLibrary(raw, demoIds), empty, `snapshot should be rejected: ${raw}`);
  }
});

test('decode drops malformed and duplicate posts but preserves valid bodies verbatim', () => {
  const boundary = { id: 'local-post-123456789012345', body: '🙂'.repeat(250) };
  const original = { id: 'local-post-1', body: '\t expanded body \r\n' };
  const decoded = decodeLibrary(persisted({ posts: [
    null,
    { id: 'local-post-0', body: 'zero ID' },
    { id: 'local-post-02', body: 'leading zero' },
    { id: 'local-post-1234567890123456', body: '16 digits' },
    { id: 'p1', body: 'demo ID is not a local post ID' },
    { id: 3, body: 'non-string ID' },
    { id: 'local-post-4', body: null },
    { id: 'local-post-5', body: ' \t\n' },
    { id: 'local-post-6', body: `${boundary.body}x` },
    original,
    { ...original, body: 'duplicate does not overwrite' },
    boundary
  ] }), demoIds);
  assert.equal(decoded.posts.length, 2);
  assert.deepEqual(decoded.posts.find(({ id }) => id === original.id), original);
  assert.deepEqual(decoded.posts.find(({ id }) => id === boundary.id), boundary);
});

test('likes and bookmarks can refer to demo or retained local posts, but follows are demo-only', () => {
  const post = { id: 'local-post-1', body: 'valid local post' };
  const rejected = ['unknown-demo', 'local-post-7', 'local-post-02', null, 1];
  const decoded = decodeLibrary(persisted({
    posts: [{ id: 'local-post-7', body: '  ' }, post],
    likedIds: ['p1', ...rejected, post.id],
    followedIds: [post.id, ...rejected, 'p2'],
    savedIds: [...rejected, post.id, 'p2']
  }), demoIds);
  assert.deepEqual(decoded.posts, [post]);
  assert.deepEqual(decoded.likedIds, ['p1', post.id]);
  assert.deepEqual(decoded.followedIds, ['p2']);
  assert.deepEqual(decoded.savedIds, [post.id, 'p2']);
});

test('the 40-post cap counts valid distinct local posts, not input entries', () => {
  const posts = Array.from({ length: 41 }, (_, i) => ({ id: `local-post-${i + 1}`, body: `Post ${i + 1}` }));
  const decoded = decodeLibrary(persisted({
    posts: [null, posts[0], posts[0], ...posts.slice(1)],
    likedIds: posts.map(({ id }) => id),
    savedIds: posts.map(({ id }) => id)
  }), demoIds);
  const ids = new Set(decoded.posts.map(({ id }) => id));
  assert.equal(decoded.posts.length, 40);
  assert.equal(ids.size, 40);
  assert.deepEqual(new Set(decoded.likedIds), ids);
  assert.deepEqual(new Set(decoded.savedIds), ids);
});

test('a local photo reference is not a path and a photo-only post survives a library round trip', () => {
  const photoKey = `photo-${'a'.repeat(32)}.jpg`;
  const invalid = ['../' + photoKey, 'file://' + photoKey, photoKey + '\n', { length: 42 }, null];
  assert.equal(isPostPhotoKey(photoKey), true);
  assert.ok(invalid.every((key) => !isPostPhotoKey(key)));
  assert.equal(canKeepPost('  ', photoKey), true);
  assert.equal(canKeepPost('x'.repeat(501), photoKey), false);
  const post = { id: 'local-post-1', body: '', photoKey };
  const state = decodeLibrary(persisted({ posts: [post,
    { id: 'local-post-2', body: '', photoKey: '../image.jpg' },
    { id: 'local-post-3', body: 'Keep the text', photoKey: 'https://example.test/photo' }] }), demoIds);
  assert.deepEqual(state.posts, [post, { id: 'local-post-3', body: 'Keep the text' }]);
  assert.deepEqual(decodeLibrary(encodeLibrary(state), demoIds), state);
});

test('the draft holds text and one local photo together and never exposes arbitrary URLs', () => {
  const photoKey = `photo-${'b'.repeat(32)}.jpg`;
  assert.deepEqual(decodePostDraft(JSON.stringify({ body: '', photoKey })), { body: '', photoKey });
  assert.deepEqual(decodePostDraft(JSON.stringify({ body: '\n  caption ', photoKey: 'file:///elsewhere' })),
    { body: '\n  caption ' });
  assert.throws(() => decodePostDraft(JSON.stringify({ body: 'x'.repeat(501), photoKey })));
});

test('search is trimmed, case-insensitive, and requires every term across the fields', () => {
  const matches = (query) => matchesPost(query, 'Mina Chen', '@Skyline', 'A quiet morning in 杭州');
  assert.equal(matches(' \t\n '), true);
  assert.equal(matches('  mInA\t@SKYLINE\nMORNING  '), true);
  assert.equal(matches('杭州 quiet'), true);
  assert.equal(matches('Chen @skyline midnight'), false);
});
