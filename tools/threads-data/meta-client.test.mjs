import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createThreadsClient, ThreadsDataError } from './meta-client.mjs';

const TOKEN = 'fake-bearer-do-not-disclose';
const FIELDS = 'id,username,text,permalink,timestamp,media_type';
const SAMPLE = {
  id: '1234', username: 'sample.reader', text: 'A fictional walk by the lake 📝',
  permalink: 'https://www.threads.com/@sample.reader/post/abc-1?tracking=discard#fragment',
  timestamp: '2025-04-04T09:20:45+0000', media_type: 'TEXT', ignored: 'not published',
};
const POST = {
  id: '1234', username: 'sample.reader', text: SAMPLE.text,
  permalink: 'https://www.threads.com/@sample.reader/post/abc-1',
  timestamp: SAMPLE.timestamp, mediaType: 'TEXT',
};

function fake(fetchImpl, options = {}) {
  return createThreadsClient({ token: TOKEN, fetchImpl, ...options });
}

function hasCode(code, sensitive = TOKEN) {
  return error => {
    assert.ok(error instanceof ThreadsDataError);
    assert.equal(error.code, code);
    assert.equal(error.cause, undefined);
    assert.ok(!String(error.stack).includes(sensitive));
    assert.ok(!JSON.stringify(error).includes(sensitive));
    return true;
  };
}

test('GET only on official paths, uses Bearer, whitelists output and paginates via after alone', async () => {
  const calls = [];
  const client = fake(async (url, options) => {
    calls.push([new URL(url), options]);
    if (url.pathname === '/me') return Response.json({ id: '88', username: 'sample.reader', name: 'not requested' });
    return Response.json({ data: [SAMPLE], paging: {
      cursors: { before: 'never-used', after: 'QSti/==~' },
      next: `https://other.invalid/?access_token=${TOKEN}`,
    } });
  }, { baseUrl: 'https://other.invalid' });

  assert.deepEqual(await client.search('  湖辺 & 搜索 = #  '), { posts: [POST], nextCursor: 'QSti/==~' });
  assert.deepEqual(await client.profilePosts('@sample.reader', 'QSti/==~'), { posts: [POST], nextCursor: '' });
  assert.deepEqual(await client.account(), { id: '88', username: 'sample.reader' });
  assert.deepEqual(calls.map(([url]) => url.pathname), ['/keyword_search', '/profile_posts', '/me']);
  assert.deepEqual(Object.fromEntries(calls[0][0].searchParams), {
    q: '湖辺 & 搜索 = #', search_type: 'RECENT', fields: FIELDS, limit: '25',
  });
  assert.deepEqual(Object.fromEntries(calls[1][0].searchParams), {
    username: 'sample.reader', fields: FIELDS, after: 'QSti/==~',
  });
  assert.deepEqual(Object.fromEntries(calls[2][0].searchParams), { fields: 'id,username' });
  for (const [url, options] of calls) {
    assert.equal(url.origin, 'https://graph.threads.com');
    assert.ok(!url.href.includes(TOKEN));
    assert.equal(options.method, 'GET');
    assert.equal(options.headers.Authorization, `Bearer ${TOKEN}`);
    assert.equal(options.redirect, 'error');
    assert.equal(options.credentials, 'omit');
    assert.equal(options.referrerPolicy, 'no-referrer');
    assert.ok(options.signal instanceof AbortSignal);
  }
});

test('validates request input and credentials before invoking fetch', async () => {
  let calls = 0;
  const fetchImpl = async () => { calls++; return Response.json({ data: [] }); };
  const client = fake(fetchImpl);
  for (const value of [null, 1, '', '   ', 'a\tb', 'a\u0085b', 'x'.repeat(201), `not for URL ${TOKEN}`]) {
    await assert.rejects(client.search(value), hasCode('invalid_input'));
  }
  for (const value of ['@@who', '@', 'x/y', '../x', 'a?next=1', 'twó', 'x'.repeat(31), 'xy\n']) {
    await assert.rejects(client.profilePosts(value), hasCode('invalid_input'));
  }
  for (const value of [null, 'A&access_token=x', 'a\n', 'https://other.invalid', 'x'.repeat(2049), TOKEN]) {
    await assert.rejects(client.search('sample', value), hasCode('invalid_input'));
  }
  for (const token of [undefined, '', 'bearer with spaces', 'token\r\nInjected: x', 'x'.repeat(4097)]) {
    await assert.rejects(createThreadsClient({ token, fetchImpl }).search('sample'), hasCode('unconfigured'));
  }
  assert.equal(calls, 0);
});

test('rejects redirects and unexpected response URLs without sending another request', async () => {
  let calls = 0;
  const target = 'https://other.invalid/as-redirect';
  const changedUrl = new Response('{}');
  Object.defineProperty(changedUrl, 'url', { value: target });
  const alreadyFollowed = new Response('{}');
  Object.defineProperty(alreadyFollowed, 'redirected', { value: true });
  const opaque = new Response('{}');
  Object.defineProperty(opaque, 'type', { value: 'opaqueredirect' });
  for (const response of [Response.redirect(target), alreadyFollowed, changedUrl, opaque]) {
    const client = fake(async () => { calls++; return response; });
    await assert.rejects(client.search('sample'), hasCode('upstream'));
  }
  assert.equal(calls, 4);
});

test('drops unsafe external or non-post links and redacts literal token echoes from successes', async () => {
  const unsafe = [
    'http://www.threads.com/@sample.reader/post/abcd', 'https://www.threads.com.evil.invalid/@a/post/abcd',
    'https://www.threads.com:123/@a/post/abcd', 'https://name:pw@www.threads.com/@a/post/abcd',
    'https://graph.threads.com/@a/post/abcd', 'https://www.threads.com/@a', 'https://www.threads.com/@a/post/%2fabcd',
    '//www.threads.com/@a/post/abcd', 'javascript:alert(1)', 'https://www.threads.com\\@a/post/abcd',
    `https://www.threads.com/@a/post/${TOKEN}`, 'https://www.threads.com/@a/post/abcd\n',
  ];
  const client = fake(async (url) => Response.json(url.pathname === '/me' ? { id: TOKEN, username: 'some.reader' } : {
    data: [
      ...unsafe.map((permalink, i) => ({ ...SAMPLE, id: String(i), text: TOKEN, permalink })),
      { ...SAMPLE, id: TOKEN }, { ...SAMPLE, username: 'invalid username' }, null,
      { ...SAMPLE, permalink: `https://www.threads.net/@a/post/abcd?access_token=${TOKEN}` },
    ],
    paging: { cursors: { after: TOKEN }, next: 'https://other.invalid' },
  }));
  const result = await client.search('sample');
  assert.equal(result.posts.length, unsafe.length + 1);
  assert.ok(result.posts.slice(0, -1).every(post => post.permalink === '' && post.text === ''));
  assert.equal(result.posts.at(-1).permalink, 'https://www.threads.net/@a/post/abcd');
  assert.equal(result.nextCursor, '');
  assert.ok(!JSON.stringify(result).includes(TOKEN));
  await assert.rejects(client.account(), hasCode('upstream'));
});

test('bounds entries and fields, and ignores next URLs and malformed cursors', async () => {
  const row = { id: '999', username: 'sample.reader', text: 'x'.repeat(4200), timestamp: 'nonsense', media_type: {} };
  for (const after of [undefined, 1, 'x'.repeat(2049), 'https://other.invalid/']) {
    const client = fake(async () => Response.json({ data: Array(40).fill(row), paging: {
      cursors: { after }, next: 'https://other.invalid?after=must-not-extract',
    } }));
    const page = await client.profilePosts('sample.reader');
    assert.equal(page.posts.length, 25);
    assert.deepEqual(page.posts[0], {
      id: '999', username: 'sample.reader', text: 'x'.repeat(4096), permalink: '', timestamp: '', mediaType: '',
    });
    assert.equal(page.nextCursor, '');
  }
});

test('bounds declared and streamed bytes, and cancels oversize streams', async () => {
  for (const trustedLength of ['262145', null]) {
    let cancelled = false;
    const body = new ReadableStream({
      start(controller) { controller.enqueue(new Uint8Array(256 * 1024 + 1)); },
      cancel() { cancelled = true; },
    });
    const headers = trustedLength ? { 'content-length': trustedLength } : {};
    const client = fake(async () => new Response(body, { headers }));
    await assert.rejects(client.search('sample'), hasCode('upstream'));
    assert.equal(cancelled, true);
  }
});

test('maps Graph codes, HTTP failures, malformed JSON and transport failures without leaking details', async () => {
  const errors = [
    [400, 190, 'unauthorized'], [400, 102, 'unauthorized'], [401, null, 'unauthorized'],
    [400, 10, 'permission'], [400, '200', 'permission'], [403, null, 'permission'],
    [200, 4, 'rate_limited'], [400, 613, 'rate_limited'], [429, null, 'rate_limited'],
    [400, 100, 'invalid_input'], [400, 'bad', 'upstream'], [503, null, 'upstream'], [200, null, 'upstream'],
  ];
  for (const [status, code, category] of errors) {
    const response = code === null ? new Response(`invalid JSON ${TOKEN}`, { status }) :
      Response.json({ error: { code, message: TOKEN, fbtrace_id: TOKEN } }, { status });
    await assert.rejects(fake(async () => response).search('sample'), hasCode(category));
  }
  const malformed = fake(async () => Response.json({ data: {}, paging: { next: 'https://other.invalid' } }));
  await assert.rejects(malformed.search('sample'), hasCode('upstream'));
  await assert.rejects(fake(async () => { throw new Error(TOKEN); }).search('sample'), hasCode('network'));
});

test('the deadline covers stalled headers and body, aborts I/O, and handles a caller abort', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let signal;
  const pendingHeaders = fake(async (_, options) => {
    signal = options.signal;
    return new Promise(() => {});
  }).search('sample');
  t.mock.timers.tick(8000);
  await assert.rejects(pendingHeaders, hasCode('network'));
  assert.equal(signal.aborted, true);

  let cancelled = false;
  let startReading;
  const reading = new Promise(resolve => { startReading = resolve; });
  const body = new ReadableStream({
    pull() { startReading(); },
    cancel() { cancelled = true; },
  }, { highWaterMark: 0 });
  const pendingBody = fake(async () => new Response(body)).search('sample');
  await reading;
  t.mock.timers.tick(8000);
  await assert.rejects(pendingBody, hasCode('network'));
  assert.equal(cancelled, true);

  const caller = new AbortController();
  const pendingCaller = fake(async (_, options) => {
    signal = options.signal;
    return new Promise(() => {});
  }).profilePosts('sample.reader', '', { signal: caller.signal });
  caller.abort(new Error(TOKEN));
  await assert.rejects(pendingCaller, hasCode('network'));
  assert.equal(signal.aborted, true);
  await assert.rejects(fake(async () => assert.fail('pre-aborted request reached fetch')).account({ signal: caller.signal }),
    hasCode('network'));
});
