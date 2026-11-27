import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const source = readFileSync(new URL('../app/entry/src/main/ets/model/LocalLibrary.ets', import.meta.url), 'utf8');
const modelUrl = `data:text/javascript,${encodeURIComponent(stripTypeScriptTypes(source))}`;
const { LIBRARY_POST_LIMIT, LIBRARY_REPLY_LIMIT, LOCAL_POST_BODY_LIMIT, LOCAL_REPLY_BODY_LIMIT, MAX_POST_PHOTOS,
  MAX_THREAD_PARTS, canKeepPost, canPublishThread, decodeLibrary, decodePostDraft, emptyLibrary, encodeLibrary,
  isPostPhotoKey, matchesPost } = await import(modelUrl);

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

const photo = (hex) => `photo-${hex.repeat(32)}.jpg`;

test('only lowercase, basename-only photo keys can keep a photo-only post', () => {
  const key = photo('a');
  const invalid = ['../' + key, 'file://' + key, key + '\n', photo('A'), { length: 42 }, null];
  assert.equal(isPostPhotoKey(key), true);
  assert.ok(invalid.every((value) => !isPostPhotoKey(value)));
  assert.equal(canKeepPost('  ', [key]), true);
  assert.equal(canKeepPost('  ', invalid), false);
  assert.equal(canKeepPost('  ', []), false);
  assert.equal(canKeepPost('caption', []), true);
  assert.equal(canKeepPost('x'.repeat(501), [key]), false);
});

test('version 1 legacy photos migrate to arrays, plain posts keep their disk shape', () => {
  const key = photo('a');
  const posts = [
    { id: 'local-post-1', body: '', photoKeys: [key] },
    { id: 'local-post-3', body: 'Keep the text' }
  ];
  const state = decodeLibrary(persisted({ posts: [
    { id: 'local-post-1', body: '', photoKey: key },
    { id: 'local-post-2', body: '', photoKey: '../image.jpg' },
    { id: 'local-post-3', body: 'Keep the text', photoKey: 'https://example.test/photo' }
  ] }), demoIds);
  assert.deepEqual(state.posts, posts);
  const encoded = encodeLibrary(state);
  assert.deepEqual(JSON.parse(encoded), { version: 1, ...empty, posts });
  assert.deepEqual(decodeLibrary(encoded, demoIds), state);
});

test('canonical library arrays are sanitized in order and never fall back to legacy photos', () => {
  const [a, b, c, d, e, legacyKey] = ['a', 'b', 'c', 'd', 'e', 'f'].map(photo);
  assert.equal(MAX_POST_PHOTOS, 4);
  const state = decodeLibrary(persisted({ posts: [
    { id: 'local-post-1', body: '', photoKeys: [b, null, b, a, photo('F'), '../foo.jpg', d, c, e], photoKey: legacyKey },
    { id: 'local-post-2', body: 'Caption', photoKeys: [], photoKey: legacyKey },
    { id: 'local-post-3', body: ' ', photoKeys: ['https://example.test/photo', false], photoKey: legacyKey },
    { id: 'local-post-4', body: 'Not an array', photoKeys: a }
  ], likedIds: ['local-post-1', 'local-post-3'] }), demoIds);
  assert.deepEqual(state.posts, [
    { id: 'local-post-1', body: '', photoKeys: [b, a, d, c] },
    { id: 'local-post-2', body: 'Caption' },
    { id: 'local-post-4', body: 'Not an array' }
  ]);
  assert.deepEqual(state.likedIds, ['local-post-1']);
  assert.deepEqual(decodeLibrary(encodeLibrary(state), demoIds), state);
});

test('draft restoration migrates old keys and sanitizes canonical arrays with the same precedence', () => {
  const [a, b, c, d, e] = ['a', 'b', 'c', 'd', 'e'].map(photo);
  const decode = (fields) => decodePostDraft(JSON.stringify(fields));
  const body = '\n  caption ';
  assert.deepEqual(decode({ body }), { body });
  assert.deepEqual(decode({ body: '', photoKey: a }), { body: '', photoKeys: [a] });
  assert.deepEqual(decode({ body, photoKey: 'file:///elsewhere' }), { body });
  assert.deepEqual(decode({ body, photoKeys: [], photoKey: a }), { body });
  assert.deepEqual(decode({ body, photoKeys: [42, null, {}], photoKey: a }), { body });
  assert.deepEqual(decode({ body, photoKeys: [b, null, b, a, c, d, e], photoKey: e }), { body, photoKeys: [b, a, c, d] });
  assert.throws(() => decode({ body: 'x'.repeat(501), photoKeys: [a] }), /Invalid local draft/);
});

test('video-only posts and drafts retain validated duration without rewriting legacy photos', () => {
  const key = `video-${'a'.repeat(32)}.mp4`;
  const video = { key, durationMs: 60000 };
  const picture = photo('b');
  const posts = [
    { id: 'local-post-1', body: '', video },
    { id: 'local-post-2', body: '', photoKeys: [picture] },
    { id: 'local-post-3', body: 'Keep the caption' }
  ];
  const invalid = [null, { key: '../' + key, durationMs: 1 }, { key, durationMs: 0 },
    { key, durationMs: '1500' }, { key, durationMs: 1000.5 }, { key, durationMs: 60001 }];
  assert.equal(canKeepPost('', [], video), true);
  assert.equal(canKeepPost('x'.repeat(501), [], video), false);
  assert.ok(invalid.every((item) => !canKeepPost('', [], item)));
  assert.deepEqual(decodePostDraft(JSON.stringify({ body: '', video })), { body: '', video });
  assert.deepEqual(decodePostDraft(JSON.stringify({ body: '', photoKey: picture, video })), { body: '', photoKeys: [picture] });
  const state = decodeLibrary(persisted({ posts: [
    { ...posts[0], video: { ...video, fileUri: 'file:///ignored' } },
    { id: 'local-post-2', body: '', photoKey: picture, video },
    { ...posts[2], video: invalid[1] },
    { id: 'local-post-4', body: '', video: invalid.at(-1) }
  ] }), demoIds);
  assert.deepEqual(state.posts, posts);
  assert.deepEqual(decodeLibrary(encodeLibrary(state), demoIds), state);
});

test('legacy single-post encoding stays byte-for-byte version 1', () => {
  const picture = photo('a');
  const video = { key: `video-${'f'.repeat(32)}.mp4`, durationMs: 1234 };
  const state = { ...empty, posts: [
    { id: 'local-post-1', body: 'Text' },
    { id: 'local-post-2', body: '', photoKeys: [picture] },
    { id: 'local-post-3', body: '', video }
  ] };
  const expected = JSON.stringify({ version: 1, posts: state.posts, likedIds: [], followedIds: [], savedIds: [],
    replies: [], hiddenIds: [] });
  assert.equal(encodeLibrary(state), expected);
  assert.deepEqual(decodeLibrary(expected, demoIds), state);
});

test('draft continuations retain blank segments, media and order without changing root sanitization', () => {
  const a = photo('a');
  const b = photo('b');
  const video = { key: `video-${'a'.repeat(32)}.mp4`, durationMs: 60000 };
  const continuation = [{ body: '  ' }, { body: '', photoKeys: [b, a] }, { body: '' }, { body: '', video },
    { body: '\n最後の段落\t ' }];
  const draft = { body: '', photoKeys: [a], continuation };
  assert.deepEqual(decodePostDraft(JSON.stringify({ ...draft, photoKeys: [a, '../broken', a], video })), draft);
  assert.deepEqual(decodePostDraft(JSON.stringify(draft)), draft);
  assert.deepEqual(decodePostDraft('{"body":"","continuation":[]}'), { body: '', continuation: [] });
  assert.deepEqual(decodePostDraft('{"body":"","continuation":[{"body":""}]}'),
    { body: '', continuation: [{ body: '' }] });
});

test('malformed draft continuations throw instead of appearing to be a valid shorter draft', () => {
  const picture = photo('a');
  const video = { key: `video-${'f'.repeat(32)}.mp4`, durationMs: 1234 };
  for (const continuation of [null, {}, '', [null], [1], [[]], [{}], [{ body: 3 }],
    [{ body: 'x'.repeat(LOCAL_POST_BODY_LIMIT + 1) }], [{ body: '', continuation: [] }],
    [{ body: '', photoKeys: picture }], [{ body: '', photoKeys: [picture, picture] }],
    [{ body: '', photoKeys: ['a', 'b', 'c', 'd', 'e'].map(photo) }],
    [{ body: '', photoKeys: [picture, '../broken'] }], [{ body: '', video: { ...video, durationMs: 0 } }],
    [{ body: '', photoKeys: [picture], video }], Array.from({ length: MAX_THREAD_PARTS }, () => ({ body: '' }))]) {
    assert.throws(() => decodePostDraft(JSON.stringify({ body: 'must not overwrite', continuation })),
      /Invalid local draft/);
  }
});

test('publishing requires valid nonempty content in every part and enforces media and segment limits', () => {
  assert.equal(MAX_THREAD_PARTS, 6);
  const pictures = ['a', 'b', 'c', 'd', 'e'].map(photo);
  const video = { key: `video-${'b'.repeat(32)}.mp4`, durationMs: 60000 };
  const root = { body: 'x'.repeat(LOCAL_POST_BODY_LIMIT) };
  const continuation = [{ body: 'second' }, { body: '', photoKeys: pictures.slice(0, 4) }, { body: ' ', video },
    { body: 'fifth' }, { body: 'sixth' }];
  assert.equal(canPublishThread(root, []), true);
  assert.equal(canPublishThread(root, continuation), true);
  assert.equal(canPublishThread(root, [...continuation, root]), false);
  assert.equal(canPublishThread({ body: ' ' }, continuation), false);
  for (const part of [null, { body: ' ' }, { body: 'x'.repeat(LOCAL_POST_BODY_LIMIT + 1) },
    { body: 'text', photoKeys: [pictures[0], null] }, { body: 'text', photoKeys: pictures },
    { body: 'text', photoKeys: [pictures[0], pictures[0]] }, { body: 'text', photoKeys: [pictures[0]], video },
    { body: 'text', video: { ...video, durationMs: 60001 } }]) {
    assert.equal(canPublishThread(part, []), false);
    assert.equal(canPublishThread(root, [part]), false);
  }
  assert.equal(canPublishThread(root, null), false);
  assert.equal(canPublishThread(root, new Array(1)), false);
});

test('version 1 round-trips whole threads; encode and decode discard malformed threads atomically', () => {
  const picture = photo('a');
  const video = { key: `video-${'c'.repeat(32)}.mp4`, durationMs: 1000 };
  const thread = { id: 'local-post-1', body: '', video, continuation: [
    { body: '\t second\n' }, { body: '', photoKeys: [picture] }, { body: 'fourth' }
  ] };
  const single = { id: 'local-post-2', body: 'single' };
  const bad = [
    { ...thread, continuation: null },
    { ...thread, continuation: [{ body: 'keep nothing' }, { body: ' ' }] },
    { ...thread, continuation: [{ body: '', photoKeys: [picture], video }] },
    { ...thread, continuation: [{ body: 'text', photoKeys: ['../broken'] }] },
    { ...thread, continuation: [{ body: '', video: { ...video, durationMs: -1 } }] },
    { ...thread, continuation: [{ body: 'x'.repeat(LOCAL_POST_BODY_LIMIT + 1) }] },
    { ...thread, continuation: Array.from({ length: MAX_THREAD_PARTS }, () => ({ body: 'too many parts' })) },
    { ...thread, photoKeys: [picture] },
    { ...thread, photoKey: picture },
    { ...thread, video: undefined },
    { ...thread, body: 'x'.repeat(LOCAL_POST_BODY_LIMIT + 1) }
  ].map((post, i) => ({ ...post, id: `local-post-${i + 3}` }));
  const state = { ...empty, posts: [...bad, thread, single] };
  const retained = { ...empty, posts: [thread, single] };
  const encoded = encodeLibrary(state);
  assert.deepEqual(JSON.parse(encoded), { version: 1, ...retained });
  assert.deepEqual(decodeLibrary(encoded, demoIds), retained);
  assert.deepEqual(decodeLibrary(persisted(state), demoIds), retained);
  assert.deepEqual(decodeLibrary(persisted({ ...state, likedIds: [bad[0].id, thread.id] }), demoIds).likedIds,
    [thread.id]);
});

test('storage bounds cover 40 six-part posts with worst-case JSON escapes, four keys per part and 80 replies', () => {
  const maxPart = (n) => ({ body: '\u0001'.repeat(LOCAL_POST_BODY_LIMIT), photoKeys:
    Array.from({ length: MAX_POST_PHOTOS }, (_, i) => `photo-${(n * MAX_POST_PHOTOS + i).toString(16).padStart(32, '0')}.jpg`) });
  const maxDraft = (n) => ({ ...maxPart(n * MAX_THREAD_PARTS), continuation:
    Array.from({ length: MAX_THREAD_PARTS - 1 }, (_, i) => maxPart(n * MAX_THREAD_PARTS + i + 1)) });
  const draft = maxDraft(0);
  const raw = JSON.stringify(draft);
  assert.ok(raw.length > 4000);
  assert.deepEqual(decodePostDraft(raw), draft);
  const posts = Array.from({ length: LIBRARY_POST_LIMIT }, (_, i) => ({ id: `local-post-${100000000000000 + i}`,
    ...maxDraft(i) }));
  const replies = Array.from({ length: LIBRARY_REPLY_LIMIT }, (_, i) => ({ id: `local-${100000000000000 + i}`,
    postId: posts[0].id, body: '\u0001'.repeat(LOCAL_REPLY_BODY_LIMIT),
    parentId: i === 0 ? undefined : `local-${100000000000000 + i - 1}` }));
  const state = { ...empty, posts, likedIds: [...demoIds, ...posts.map(({ id }) => id)],
    savedIds: [...demoIds, ...posts.map(({ id }) => id)], followedIds: demoIds, hiddenIds: demoIds, replies };
  const encoded = encodeLibrary(state);
  assert.ok(encoded.length > 350000);
  assert.deepEqual(decodeLibrary(encoded, demoIds), state);
  const overflow = { id: 'local-post-999999999999999', ...maxDraft(LIBRARY_POST_LIMIT) };
  const invalid = { id: 'local-post-2', body: 'broken', continuation: [{ body: '' }] };
  assert.deepEqual(decodeLibrary(persisted({ ...state, posts: [invalid, ...posts, overflow] }), demoIds), state);
});

test('search is trimmed, case-insensitive, and requires every term across the fields', () => {
  const matches = (query) => matchesPost(query, 'Mina Chen', '@Skyline', 'A quiet morning in 杭州');
  assert.equal(matches(' \t\n '), true);
  assert.equal(matches('  mInA\t@SKYLINE\nMORNING  '), true);
  assert.equal(matches('杭州 quiet'), true);
  assert.equal(matches('Chen @skyline midnight'), false);
});
