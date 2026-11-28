import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';
import vm from 'node:vm';

const stage = readFileSync(new URL('../app/entry/src/main/ets/pages/Index.ets', import.meta.url));
const overlay = readFileSync(new URL('../overlay/entry/src/main/ets/pages/Index.ets', import.meta.url));
const source = stage.toString('utf8');

const home = 'https://www.threads.com/';
const author = `${home}@some.one`;
const post = 'https://threads.net/@reader/post/ABC_123/';
const resumeStore = 'threads_public_resume';
const proxyStore = 'threads_settings';

function between(start, end) {
  const first = source.indexOf(start);
  const last = source.indexOf(end, first + start.length);
  assert.ok(first >= 0 && last > first, `missing range: ${start} → ${end}`);
  return source.slice(first, last);
}

const runtimeSource = stripTypeScriptTypes(`${between('const HOME_URL:', '@Entry')}
class Index {
  ${between('  private controller:', '  @Builder').replace(/^  (?:@State )?private /gm, '  ')}
}
[Index, publicThreadsTarget]`);

function harness(stored) {
  const disk = new Map([[resumeStore, new Map(stored === undefined ? [] : [['target', stored]])]]);
  const accesses = [];
  const mutations = [];
  const navigations = [];
  const options = { failRead: false, failFlush: false };
  const [Index, publicTarget] = vm.runInNewContext(runtimeSource, {
    url: { URL: { parseURL: value => new URL(value) } },
    webview: { WebviewController: class {
      current = '';
      getUrl() { return this.current; }
      loadUrl(value) { navigations.push(value); this.current = value; }
      stop() {}
    } },
    preferences: {
      getPreferencesSync(_context, { name }) {
        accesses.push(name);
        if (name === resumeStore && options.failRead) throw new Error('read failed');
        const data = new Map(disk.get(name));
        return {
          getSync: (key, fallback) => data.has(key) ? data.get(key) : fallback,
          putSync: (key, value) => { mutations.push([name, 'put', key, value]); data.set(key, value); },
          deleteSync: key => { mutations.push([name, 'delete', key]); data.delete(key); },
          flushSync: () => {
            if (options.failFlush) throw new Error('flush failed');
            disk.set(name, new Map(data));
          },
        };
      },
    },
    getContext: page => page,
    router: { getLength: () => 0 },
    setTimeout: () => 1,
    clearTimeout: () => {},
  });
  const attach = () => {
    const page = new Index();
    page.webReady = true;
    page.initializeNetwork();
    page.finishLoading();
    return page;
  };
  const visit = (page, value) => {
    page.handlePageBegin(value);
    page.controller.current = value;
    page.finishLoading();
  };
  return { accesses, mutations, navigations, options, attach, visit, publicTarget,
    readDisk: () => disk.get(resumeStore).get('target') };
}

const rejected = [
  home, 'https://threads.net', `${home}login`, `${home}inbox`, `${home}search`, `${home}@reader/post/abc/replies`,
  'http://threads.com/@reader', 'https://threads.com:444/@reader', 'https://user:pass@threads.com/@reader',
  'https://www.instagram.com/@reader', 'https://auth.meta.com/@reader', 'https://threads.com.example.org/@reader',
  'https://example.org/@reader', 'https://threads.com/@reader%2fpost%2fabc', 'about:blank', 'not a URL',
];

test('explicit resume uses the official navigation guard, with home excluded only from resume', () => {
  const { publicTarget } = harness();
  assert.equal(publicTarget(home), home, 'preserve home for ordinary refresh and fallback');
  assert.equal(publicTarget('https://THREADS.NET:443/@reader/post/ABC_123/?secret=excluded#reply', false), post);
  assert.equal(publicTarget(`${author}?tracking=1#fragment`, false), author);
  for (const value of rejected) assert.equal(publicTarget(value, false), '', value);
});

test('only the explicit actions save one address, replay it after reentry, and forget it durably', () => {
  const env = harness();
  const page = env.attach();
  env.visit(page, `${author}?tracking=1#reply`);
  assert.deepEqual(env.accesses, [proxyStore]);
  assert.deepEqual(env.mutations, []);
  assert.equal(env.readDisk(), undefined);
  page.showPublicResume();
  assert.equal(page.showResume, true);
  assert.equal(page.resumeHasValue, false);
  assert.equal(env.readDisk(), undefined, 'opening the panel does not save the current page');
  page.savePublicResume();
  assert.deepEqual(env.mutations, [[resumeStore, 'put', 'target', author]]);
  assert.equal(env.readDisk(), author);
  env.visit(page, `${post}?private=1#scroll`);
  assert.equal(env.readDisk(), author, 'ordinary page starts do not overwrite the explicit value');
  page.savePublicResume();
  assert.equal(env.readDisk(), post, 'explicitly saving a new page replaces the sole value');
  assert.deepEqual(env.navigations, [home]);
  page.aboutToDisappear();
  const reopened = env.attach();
  assert.deepEqual(env.navigations, [home, home], 'startup still goes to home');
  reopened.openPublicResume();
  assert.deepEqual(env.navigations, [home, home]);
  reopened.showPublicResume();
  assert.equal(reopened.resumeTarget, post);
  assert.deepEqual(env.navigations, [home, home], 'reading Preferences is not navigation');
  reopened.openPublicResume();
  assert.equal(reopened.showResume, false);
  assert.deepEqual(env.navigations, [home, home, post]);
  assert.equal(env.mutations.length, 2, 'opening does not create a second write');
  reopened.showPublicResume();
  reopened.forgetPublicResume();
  assert.equal(reopened.resumeTarget, '');
  assert.equal(env.readDisk(), undefined);
  assert.deepEqual(env.mutations.at(-1), [resumeStore, 'delete', 'target']);
  const fresh = env.attach();
  fresh.showPublicResume();
  assert.equal(fresh.resumeHasValue, false);
  assert.equal(fresh.resumeTarget, '');
  assert.deepEqual(env.navigations, [home, home, post, home]);
});

test('save checks the live controller, not recovery state; refuses ineligible or unavailable pages', () => {
  const env = harness(author);
  const page = env.attach();
  page.showPublicResume();
  page.retryTarget = post;
  for (const value of rejected) {
    page.controller.current = value;
    page.savePublicResume();
    assert.match(page.resumeNotice, /只能保存/);
  }
  page.controller.current = post;
  page.browserFallback = true;
  page.savePublicResume();
  page.browserFallback = false;
  page.busy = true;
  page.savePublicResume();
  page.openPublicResume();
  assert.match(page.resumeNotice, /网页尚未就绪/);
  assert.equal(page.showResume, true);
  page.finishLoading();
  page.proxyPending = true;
  page.savePublicResume();
  page.openPublicResume();
  page.proxyPending = false;
  page.controller.getUrl = () => { throw new Error('detached'); };
  page.savePublicResume();
  assert.match(page.resumeNotice, /无法获取/);
  assert.deepEqual(env.mutations, []);
  assert.equal(env.readDisk(), author);
  assert.deepEqual(env.navigations, [home]);
});

test('noncanonical and invalid persisted data is neither displayed nor opened; forget remains available', () => {
  for (const stored of [true, 'https://example.org/@reader', home, `${post}?private=1#secret`]) {
    const env = harness(stored);
    const page = env.attach();
    page.showPublicResume();
    assert.equal(page.resumeTarget, '');
    assert.equal(page.resumeHasValue, true);
    assert.match(page.resumeNotice, /已存地址无效/);
    assert.doesNotMatch(page.resumeNotice, /https:|private|secret/);
    page.openPublicResume();
    assert.deepEqual(env.navigations, [home]);
    assert.deepEqual(env.mutations, []);
    page.forgetPublicResume();
    assert.equal(env.readDisk(), undefined);
  }
});

test('storage errors stay in the panel and do not report a successful save or forget', () => {
  const env = harness(author);
  const page = env.attach();
  env.options.failRead = true;
  page.showPublicResume();
  page.savePublicResume();
  page.openPublicResume();
  assert.match(page.resumeNotice, /无法读取/);
  assert.deepEqual(env.mutations, []);
  assert.deepEqual(env.navigations, [home]);
  env.options.failRead = false;
  assert.equal(page.onBackPress(), true);
  assert.equal(page.showResume, false);
  page.showPublicResume();
  assert.equal(page.resumeTarget, author);
  env.visit(page, post);
  env.options.failFlush = true;
  page.savePublicResume();
  assert.match(page.resumeNotice, /未能保存/);
  assert.equal(page.resumeTarget, author);
  assert.equal(env.readDisk(), author);
  page.forgetPublicResume();
  assert.match(page.resumeNotice, /未能忘记/);
  assert.equal(page.resumeTarget, author);
  assert.equal(env.readDisk(), author);
  env.options.failFlush = false;
  page.forgetPublicResume();
  assert.equal(env.readDisk(), undefined);
});

test('Stage and overlay match and native actions are wired from a scrollable, scalable panel', () => {
  assert.deepEqual(stage, overlay, 'Stage and overlay must be byte-identical');
  const toolbar = between('  WebToolbar() {', '  ResumeAction(');
  assert.match(toolbar, /'网页续读', 'web-resume', \(\) => \{ this\.showPublicResume\(\); \}/);
  assert.match(toolbar, /\.bindSheet\(\$\$this\.showResume, this\.PublicResumePanel\(\)/);
  const action = between('  ResumeAction(', '  PublicResumePanel()');
  assert.match(action, /constraintSize\(\{ minHeight: 48 \}\)/);
  assert.match(action, /Text\(label\)[^\n]*\.fontSize\('16fp'\)[^\n]*\.wordBreak\(/);
  assert.doesNotMatch(action, /\.height\(|\.maxLines\(/);
  assert.match(action, /\.focusable\(true\)\.focusBox\(/);
  assert.match(action, /\.accessibilityGroup\(true\)\.accessibilityText\(label\)/);
  const panel = between('  PublicResumePanel()', '  SettingsPanel()');
  assert.match(panel, /Scroll\(\)/);
  assert.match(panel, /Text\(this\.resumeTarget\)[\s\S]*?\.wordBreak\(/);
  assert.match(panel, /'web-resume-save'[\s\S]*?this\.savePublicResume\(\)/);
  assert.match(panel, /'web-resume-open', true, true,[\s\S]*?this\.openPublicResume\(\)/);
  assert.match(panel, /'web-resume-forget'[^\n]*this\.forgetPublicResume\(\)/);
  assert.match(panel, /'web-resume-close'[^\n]*this\.showResume = false/);
  for (const method of ['showPublicResume', 'savePublicResume', 'openPublicResume', 'forgetPublicResume']) {
    assert.equal(source.match(new RegExp(`this\\.${method}\\(`, 'g'))?.length, 1, `${method} is user-action-only`);
  }
});
