import assert from 'node:assert/strict';
import { once } from 'node:events';
import { request } from 'node:http';
import test from 'node:test';
import { startDevRelay } from './dev-relay.mjs';
import { createThreadsClient } from './meta-client.mjs';

const route = '/v1/public-posts';
const search = `${route}?mode=search&q=hello`;
const post = {
  id: 'post_1', username: 'alice', text: '你好 Threads',
  permalink: 'https://www.threads.com/@alice/post/post_1',
  timestamp: '2026-11-27T09:00:00Z', mediaType: 'TEXT_POST',
};
const emptyPage = { posts: [], nextCursor: '' };

async function relay(t, options) {
  const server = await startDevRelay({ port: 0, ...options });
  t.after(() => {
    const closed = once(server, 'close');
    server.close();
    server.closeAllConnections();
    return closed;
  });
  return server;
}

function send(server, path = search, { method = 'GET', headers, body } = {}) {
  const { port } = server.address();
  return new Promise((resolve, reject) => {
    const req = request({ hostname: '127.0.0.1', port, path, method, headers, agent: false }, res => {
      res.setEncoding('utf8');
      let raw = '';
      res.on('data', chunk => { raw += chunk; });
      res.on('error', reject);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, headers: res.headers, body: raw ? JSON.parse(raw) : null });
        } catch (error) {
          reject(error);
        }
      });
    });
    req.on('error', reject);
    req.end(body);
  });
}

function expectError(response, status, code) {
  assert.equal(response.status, status);
  assert.deepEqual(response.body, { error: code });
  assert.equal(response.headers['content-type'], 'application/json; charset=utf-8');
  assert.equal(response.headers['cache-control'], 'no-store');
  assert.ok(!Object.keys(response.headers).some(name => name.startsWith('access-control-')));
}

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

test('binds to IPv4 loopback and dispatches only the public page contract', async t => {
  const calls = [];
  const page = { posts: [{ ...post, privateField: 'discard' }], nextCursor: 'next+/=', raw: 'discard' };
  const server = await relay(t, {
    client: {
      search(q, cursor, { signal }) {
        assert.ok(signal instanceof AbortSignal);
        calls.push(['search', q, cursor]);
        return page;
      },
      profilePosts(q, cursor) {
        calls.push(['profile', q, cursor]);
        return emptyPage;
      },
    },
  });
  assert.equal(server.address().address, '127.0.0.1');
  assert.equal(server.address().family, 'IPv4');
  const result = await send(server, `${route}?mode=search&q=${encodeURIComponent(' 你好 & Threads ')}&cursor=first%2B%2F%3D`);
  assert.equal(result.status, 200);
  assert.deepEqual(result.body, { posts: [post], nextCursor: 'next+/=' });
  assert.equal(result.headers['cache-control'], 'no-store');
  assert.equal(result.headers['x-content-type-options'], 'nosniff');
  assert.equal(result.headers['access-control-allow-origin'], undefined);
  assert.deepEqual((await send(server, `${route}?mode=profile&q=%40Alice`)).body, emptyPage);
  assert.deepEqual(calls, [['search', '你好 & Threads', 'first+/='], ['profile', '@Alice', '']]);
});

test('refuses nonexact authority and browser-originated requests without CORS', async t => {
  let calls = 0;
  const server = await relay(t, { client: { search() { calls++; return emptyPage; } } });
  const port = server.address().port;
  const wrongPort = port === 65535 ? port - 1 : port + 1;
  for (const headers of [
    { Host: `foreign.example:${port}` },
    { Host: `localhost:${port}` },
    { Host: `127.0.0.1:${wrongPort}` },
    { Host: '127.0.0.1' },
    ['Host', `127.0.0.1:${port}`, 'Host', `foreign.example:${port}`],
    { Origin: `http://127.0.0.1:${port}` },
    { Origin: 'https://foreign.example' },
    { Origin: 'null' },
    { Origin: '' },
    { 'Sec-Fetch-Site': 'cross-site' },
    { 'Sec-Fetch-Site': 'none' },
    { Referer: 'https://foreign.example/' },
  ]) {
    expectError(await send(server, search, { headers }), 403, 'permission');
  }
  expectError(await send(server, search, {
    method: 'OPTIONS', headers: { Origin: 'https://foreign.example', 'Access-Control-Request-Method': 'GET' },
  }), 403, 'permission');
  assert.equal(calls, 0);
});

test('rejects other routes, methods, bodies and invalid queries before upstream', async t => {
  let calls = 0;
  const server = await relay(t, { client: { search() { calls++; return emptyPage; } } });
  for (const target of [
    '/', '/health', '/v1/account', '/v1/a/../public-posts?mode=search&q=hello',
    `${route}/?mode=search&q=hello`, '/v1/public%2Dposts?mode=search&q=hello',
    `http://127.0.0.1:${server.address().port}${search}`,
  ]) {
    expectError(await send(server, target), 404, 'not_found');
  }
  const write = await send(server, search, { method: 'POST' });
  expectError(write, 405, 'method_not_allowed');
  assert.equal(write.headers.allow, 'GET');
  expectError(await send(server, search, { headers: { 'Content-Length': '1' }, body: 'x' }), 400, 'invalid_input');
  expectError(await send(server, search, { headers: { 'Transfer-Encoding': 'chunked' } }), 400, 'invalid_input');
  expectError(await send(server, search, { headers: { Expect: '100-continue', 'Content-Length': '1' } }), 400, 'invalid_input');
  for (const target of [
    route, `${route}?mode=search`, `${route}?q=hello`, `${route}?mode=unknown&q=hello`,
    `${route}?mode=search&q=+`, `${search}&q=again`, `${search}&mode=search`,
    `${search}&cursor=x&cursor=y`, `${search}&token=discard`, `${search}#fragment`,
    `${route}?mode=search&q=%C0%AF`, `${route}?mode=search&q=%`, `${route}?mode=search&q=hi%0A`,
    `${route}?mode=search&q=${'x'.repeat(201)}`, `${route}?mode=profile&q=Alice%20Bob`,
    `${search}&cursor=%25`, `${search}&cursor=${'z'.repeat(2049)}`, `${search}&cursor=${'%2B'.repeat(2700)}`,
  ]) {
    expectError(await send(server, target), 400, 'invalid_input');
  }
  assert.equal(calls, 0);
});

test('unconfigured real client wiring returns JSON 503 without touching fetch', async t => {
  let fetches = 0;
  const client = createThreadsClient({ token: undefined, fetchImpl: () => { fetches++; } });
  const server = await relay(t, { client });
  expectError(await send(server), 503, 'unconfigured');
  assert.equal(fetches, 0);
});

test('relays a normalized page from the real client with only an in-memory fake transport', async t => {
  const token = 'test-only-secret';
  const urls = [];
  const client = createThreadsClient({ token, fetchImpl: async (url, options) => {
    urls.push(url.href);
    assert.equal(options.headers.Authorization, `Bearer ${token}`);
    assert.equal(options.method, 'GET');
    return Response.json({ data: [{
      ...post, text: token, permalink: `${post.permalink}?access_token=${token}`, media_type: post.mediaType,
    }], paging: { cursors: { after: 'safe_next' } } });
  } });
  const server = await relay(t, { client });
  const result = await send(server);
  assert.equal(result.status, 200);
  assert.deepEqual(result.body, { posts: [{ ...post, text: '' }], nextCursor: 'safe_next' });
  assert.equal(urls.length, 1);
  assert.equal(urls[0].includes(token), false);
  expectError(await send(server, `${route}?mode=search&q=${token}`), 400, 'invalid_input');
  assert.equal(urls.length, 1);
});

test('maps known errors without exposing messages, upstream details, or arbitrary codes', async t => {
  const cases = [
    ['unconfigured', 503], ['invalid_input', 400], ['unauthorized', 401], ['permission', 403],
    ['rate_limited', 429], ['network', 502], ['upstream', 502], ['timeout', 504],
    ['__proto__', 502, 'upstream'], ['secret-fake-token', 502, 'upstream'],
  ];
  let current;
  const server = await relay(t, { client: { search() { throw current; } } });
  for (const [code, status, publicCode = code] of cases) {
    current = Object.assign(new Error('fake bearer, raw URL, and query'), { code });
    expectError(await send(server), status, publicCode);
  }
  current = new Error('unexpected internal error');
  expectError(await send(server), 502, 'upstream');
  const malformed = await relay(t, { client: { search: () => ({ posts: [{ id: 'bad' }] }) } });
  expectError(await send(malformed), 502, 'upstream');
  const oversized = await relay(t, { client: { search: () => ({
    posts: [{ ...post, text: '文'.repeat(100_000) }], nextCursor: '',
  }) } });
  expectError(await send(oversized), 502, 'upstream');
});

test('rejects upstream overload and admits work again when a slot settles', { timeout: 3000 }, async t => {
  const started = deferred();
  const finish = deferred();
  let calls = 0;
  const server = await relay(t, { maxConcurrent: 1, client: {
    search() {
      if (++calls === 1) {
        started.resolve();
        return finish.promise;
      }
      return emptyPage;
    },
  } });
  const first = send(server);
  await started.promise;
  expectError(await send(server), 429, 'rate_limited');
  assert.equal(calls, 1);
  finish.resolve(emptyPage);
  assert.equal((await first).status, 200);
  assert.equal((await send(server)).status, 200);
  assert.equal(calls, 2);
});

test('disconnecting the caller cancels its upstream work', { timeout: 3000 }, async t => {
  const started = deferred();
  const cancelled = deferred();
  const server = await relay(t, { maxConcurrent: 1, client: {
    search(_q, _cursor, { signal }) {
      return new Promise((_, reject) => {
        signal.addEventListener('abort', () => {
          cancelled.resolve();
          reject(new Error('aborted'));
        }, { once: true });
        started.resolve();
      });
    },
  } });
  const req = request({ hostname: '127.0.0.1', port: server.address().port, path: search, agent: false });
  req.on('error', () => {});
  req.end();
  await started.promise;
  req.destroy();
  await cancelled.promise;
});

test('relay deadline aborts the client and an abort-ignoring job still occupies its slot', async t => {
  const finish = deferred();
  let firstSignal;
  const server = await relay(t, { maxConcurrent: 1, upstreamTimeoutMs: 30, client: {
    search(_q, _cursor, { signal }) {
      if (firstSignal) return emptyPage;
      firstSignal = signal;
      return finish.promise;
    },
  } });
  expectError(await send(server), 504, 'timeout');
  assert.equal(firstSignal.aborted, true);
  expectError(await send(server), 429, 'rate_limited');
  finish.resolve(emptyPage);
  assert.equal((await send(server)).status, 200);
});
