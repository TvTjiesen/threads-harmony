import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const source = readFileSync(new URL('../../app/entry/src/main/ets/model/ThreadsReader.ets', import.meta.url), 'utf8');
const stub = `const http = new Proxy({}, { get: (_, key) => globalThis.testThreadsHttp[key] });`;
const model = await import(`data:text/javascript,${encodeURIComponent(stripTypeScriptTypes(
  source.replace("import { http } from '@kit.NetworkKit';", stub)))}`);
const post = { id: 'post_1', username: 'alice', text: '示例正文', permalink: 'https://www.threads.com/@alice/post/abc' };

test('native public reader accepts projected posts, rejects malformed rows and never opens untrusted links', () => {
  const result = model.decodeRelayPage(JSON.stringify({ posts: [post, post, null,
    { ...post, id: '../bad' }, { ...post, id: 'post_2', permalink: 'https://www.threads.com.evil.invalid/@alice/post/abc' }
  ], nextCursor: 'next+/=' }), 200);
  assert.deepEqual(result.posts.map(row => [row.id, row.permalink]), [['post_1', post.permalink], ['post_2', '']]);
  assert.equal(result.nextCursor, 'next+/=');
  assert.equal(result.error, '');
  for (const link of [post.permalink + '?tracking=x', 'https://threads.com:443/@alice/post/abc',
    'https://threads.com@evil.invalid/@alice/post/abc', 'http://threads.com/@alice/post/abc']) {
    assert.equal(model.isOfficialPostLink(link), false);
  }
  assert.match(model.decodeRelayPage('{"error":"unconfigured"}', 503).error, /尚未配置/);
  assert.match(model.decodeRelayPage('{}', 200).error, /格式/);
});

test('native public reader calls only the fixed relay, bounds requests and closes transport on success or error', async t => {
  const requests = [];
  let closed = 0;
  let offline = false;
  globalThis.testThreadsHttp = {
    RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 'STRING' },
    createHttp: () => ({
      async request(url, options) {
        requests.push({ url, options });
        if (offline) throw new Error('unavailable');
        return { result: JSON.stringify({ posts: [post], nextCursor: '' }), responseCode: 200 };
      },
      destroy() { closed++; }
    })
  };
  t.after(() => { delete globalThis.testThreadsHttp; });
  assert.match((await model.requestThreadsPosts('账号昵称', true, '')).error, /用户名/);
  assert.equal(requests.length, 0);
  assert.equal((await model.requestThreadsPosts(' 猫 & # ', false, 'after+/=')).posts[0].id, post.id);
  assert.equal(requests[0].url, 'http://127.0.0.1:18948/v1/public-posts?mode=search&q=%E7%8C%AB%20%26%20%23&cursor=after%2B%2F%3D');
  const config = requests[0].options;
  assert.equal(config.method, 'GET');
  assert.equal(config.maxRedirects, 0);
  assert.equal(config.maxLimit, 262144);
  assert.equal(config.usingProxy, false);
  assert.equal(config.usingCache, false);
  assert.deepEqual(config.header, { Accept: 'application/json' });
  offline = true;
  assert.match((await model.requestThreadsPosts(' @Alice ', true, '')).error, /无法连接开发中转/);
  assert.equal(requests[1].url, 'http://127.0.0.1:18948/v1/public-posts?mode=profile&q=Alice');
  assert.equal(closed, 2);
});
