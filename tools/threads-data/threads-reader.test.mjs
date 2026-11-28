import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import { runInNewContext } from 'node:vm';

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

const paneSource = readFileSync(new URL('../../app/entry/src/main/ets/components/ThreadsPublicPane.ets', import.meta.url), 'utf8');
function makePane(requestThreadsPosts) {
  const methods = paneSource.slice(0, paneSource.indexOf('  @Builder'))
    .replace(/^import[^\n]+\n/gm, '').replace(/^@Component\r?\n/m, '')
    .replace('export struct ThreadsPublicPane', 'class ThreadsPublicPane').replace(/@State /g, '');
  const Pane = runInNewContext(stripTypeScriptTypes(`${methods}\n}\nThreadsPublicPane;`), {
    requestThreadsPosts, SearchController: class { stopEditing() {} }, SegmentButtonV2Items: class {}
  });
  const pane = new Pane();
  pane.query = 'first';
  return pane;
}

test('pagination errors preserve existing rows and cursor and can be retried without duplicates', async () => {
  const other = { ...post, id: 'post_2' }, calls = [];
  const results = [{ posts: [post], nextCursor: 'next' }, { error: '暂时未能读取' },
    { posts: [post, other], nextCursor: '' }];
  const pane = makePane(async (...args) => { calls.push(args); return results.shift(); });
  await pane.load(false);
  await pane.load(true);
  assert.deepEqual(Array.from(pane.posts, row => row.id), ['post_1']);
  assert.deepEqual([pane.cursor, pane.notice, pane.appendNotice, pane.busy], ['next', '', '暂时未能读取', false]);
  await pane.load(true);
  assert.deepEqual(calls, [['first', false, ''], ['first', false, 'next'], ['first', false, 'next']]);
  assert.deepEqual(Array.from(pane.posts, row => row.id), ['post_1', 'post_2']);
  assert.deepEqual([pane.cursor, pane.appendNotice], ['', '']);
});

test('changing query drops in-flight results and failures from the old query', async () => {
  const pending = [];
  const pane = makePane(() => new Promise(resolve => pending.push(resolve)));
  const old = pane.load(false);
  pane.query = 'second';
  pane.clearResults();
  const current = pane.load(false);
  pending[0]({ error: '旧请求失败' });
  await old;
  assert.deepEqual([pane.notice, pane.appendNotice, pane.busy], ['', '', true]);
  pending[1]({ posts: [{ ...post, id: 'current' }], nextCursor: '' });
  await current;
  assert.deepEqual(Array.from(pane.posts, row => row.id), ['current']);
  assert.equal(pane.busy, false);
});
