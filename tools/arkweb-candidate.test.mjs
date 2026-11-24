import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import { test } from 'node:test';

const overlay = readFileSync(new URL('../overlay/entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const app = readFileSync(new URL('../app/entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const appConfig = JSON.parse(readFileSync(new URL('../app/AppScope/app.json5', import.meta.url), 'utf8'));
const buildConfig = JSON.parse(readFileSync(new URL('../app/build-profile.json5', import.meta.url), 'utf8'));

test('Stage page is synchronized with reviewed ArkWeb source', () => {
  assert.equal(app, overlay);
});

test('Stage bundle names agree and signing remains disabled', () => {
  const bundle = appConfig.app.bundleName;
  assert.equal(bundle, 'com.example.threadsharmony');
  assert.equal(buildConfig.app.products[0].bundleName, bundle);
  assert.deepEqual(buildConfig.app.signingConfigs, []);
});

test('candidate initializes only after Web attachment and gates navigation during proxy uncertainty', () => {
  assert.match(overlay, /Web\(\{ src: 'about:blank'/);
  assert.match(overlay, /onControllerAttached\(\(\) =>/);
  assert.match(overlay, /this\.initializeNetwork\(\)/);
  assert.match(overlay, /applyProxyOverride\(config, \(\) => finish\(true\)\)/);
  assert.match(overlay, /config\.insertProxyRule\(target\)/);
  assert.match(overlay, /this\.controller\.loadUrl\(HOME_URL\)/);
  assert.match(overlay, /setTimeout\(\(\) =>/);
  assert.match(overlay, /this\.controller\.stop\(\)/);
  assert.match(overlay, /private proxyPending: boolean = false/);
  assert.match(overlay, /private startupPaused: boolean = true/);
  assert.match(overlay, /private canNavigate\(\): boolean/);
  assert.match(overlay, /this\.webReady && !this\.startupPaused && !this\.proxyPending/);
  assert.match(overlay, /if \(!this\.canNavigate\(\)\) \{\s+return true;/);
  assert.match(overlay, /prefs\.flushSync\(\)/);
  assert.match(overlay, /private persistProxy\(rule: string\): boolean/);
});

test('proxy transitions serialize requests; timeout blocks navigation until the original callback', () => {
  const transition = overlay.slice(overlay.indexOf('  private changeProxy('), overlay.indexOf('  private saveProxy():'));
  assert.match(transition, /if \(!this\.webReady \|\| this\.proxyPending\)/);
  assert.match(transition, /this\.proxyPending = true/);
  assert.match(transition, /let timedOut: boolean = false/);
  const watchdog = transition.slice(transition.indexOf('const watchdog:'), transition.indexOf('const finish ='));
  assert.match(watchdog, /timedOut = true/);
  assert.match(watchdog, /系统回调超时/);
  assert.doesNotMatch(watchdog, /this\.proxyPending = false/);
  assert.doesNotMatch(watchdog, /this\.loadHome\(\)/);
  assert.match(transition, /if \(settled\) \{\s+return;/);
  assert.match(transition, /clearTimeout\(watchdog\)/);
  assert.match(transition, /this\.proxyPending = false/);
  assert.match(transition, /webview\.ProxyController\.removeProxyOverride\(\(\) => finish\(true\)\)/);
  assert.match(transition, /this\.stopLoading\(\)/);
  assert.match(overlay, /this\.controller\.stop\(\)/);
});

test('startup invalid or rejected proxy values are cleared; successful manual changes persist only after callback', () => {
  const startup = overlay.slice(overlay.indexOf('  private initializeNetwork()'), overlay.indexOf('  private persistProxy('));
  const transition = overlay.slice(overlay.indexOf('  private changeProxy('), overlay.indexOf('  private saveProxy():'));
  assert.match(startup, /typeof saved === 'string' \? normalizeProxy\(saved\) : ''/);
  assert.match(startup, /if \(rule.length === 0\)/);
  assert.match(startup, /this\.persistProxy\(''\)/);
  assert.match(transition, /if \(!success\)[\s\S]*?if \(fromSaved\)[\s\S]*?this\.persistProxy\(''\)/);
  assert.match(transition, /this\.proxyActive = target/);
  assert.match(transition, /const saved = this\.persistProxy\(target\)/);
  assert.match(transition, /if \(fromSaved && timedOut\)/);
  assert.match(transition, /this\.persistProxy\(''\)/);
});

test('fake-timer execution of production changeProxy: timeout retains lock; late startup success waits for the user', () => {
  let nextTimer = 0;
  const timers = new Map();
  let pendingApply = null;
  let pendingRemove = null;
  let applyCalls = 0;
  let removeCalls = 0;
  let rejectApply = false;
  const webview = {
    ProxyConfig: class { insertProxyRule(rule) { this.rule = rule; } },
    ProxyController: {
      applyProxyOverride: (_config, callback) => {
        applyCalls++;
        if (rejectApply) throw new Error('ArkWeb rejected the configuration');
        pendingApply = callback;
      },
      removeProxyOverride: (callback) => { removeCalls++; pendingRemove = callback; }
    }
  };
  const timerApi = {
    setTimeout: (callback) => { const id = ++nextTimer; timers.set(id, callback); return id; },
    clearTimeout: (id) => timers.delete(id)
  };
  const method = overlay.slice(overlay.indexOf('  private changeProxy('), overlay.indexOf('  private saveProxy():'))
    .replace('private changeProxy', 'changeProxy');
  const Harness = vm.runInNewContext(stripTypeScriptTypes(`const LOAD_TIMEOUT_MS = 20;\nclass Harness {
    webReady = true; proxyPending = false; startupPaused = true; proxyActive = ''; proxyInput = '';
    banner = ''; busy = false; stops = 0; navigations = 0; saved = 'old-proxy';
    stopLoading() { this.stops++; this.busy = false; }
    persistProxy(rule) { this.saved = rule; return true; }
    loadHome() { this.navigations++; }
    ${method}
    get change() { return this.changeProxy.bind(this); }
  }; Harness`), { ...timerApi, webview });

  const h = new Harness();
  h.change('old-proxy', true);
  assert.equal(h.proxyPending, true);
  assert.equal(h.navigations, 0);
  const [timerId, timeout] = [...timers.entries()][0];
  timers.delete(timerId);
  timeout();
  assert.equal(h.proxyPending, true, 'timeout must not release the in-flight lease');
  assert.equal(h.saved, '', 'startup timeout clears the rejected saved preference');
  assert.equal(h.navigations, 0, 'timeout must not navigate');
  h.change('', false);
  h.change('other-proxy', false);
  assert.equal(removeCalls, 0, 'timeout must not permit a competing removal');
  assert.equal(applyCalls, 1, 'timeout must not permit a competing application');
  const startupCallback = pendingApply;
  startupCallback();
  assert.equal(h.proxyPending, false, 'late callback settles the original request');
  assert.equal(h.startupPaused, true, 'late startup success requires explicit user confirmation');
  assert.equal(h.navigations, 0, 'late startup success must not navigate');
  assert.match(h.banner, /请在 ⚙ 中确认使用该代理/);

  const manual = new Harness();
  manual.startupPaused = false;
  manual.change('new-proxy', false);
  assert.equal(manual.saved, 'old-proxy', 'do not persist a manual target before system confirmation');
  pendingApply();
  assert.equal(manual.saved, 'new-proxy');
  assert.equal(manual.navigations, 1);

  const removal = new Harness();
  removal.startupPaused = false;
  removal.proxyActive = 'old-proxy';
  removal.change('', false);
  const [removeTimerId, removeTimeout] = [...timers.entries()][0];
  timers.delete(removeTimerId);
  removeTimeout();
  assert.equal(removal.proxyPending, true, 'remove timeout must also retain the lease');
  assert.equal(removal.navigations, 0);
  pendingRemove();
  assert.equal(removal.proxyPending, false);
  assert.equal(removal.proxyActive, '');
  assert.equal(removal.saved, '');
  assert.equal(removal.navigations, 1);

  const failedStartup = new Harness();
  rejectApply = true;
  failedStartup.change('invalid-old-proxy', true);
  assert.equal(failedStartup.proxyPending, false, 'synchronous rejection settles the operation');
  assert.equal(failedStartup.saved, '', 'synchronous rejection clears stale startup preference');
  assert.equal(failedStartup.startupPaused, true);
  rejectApply = false;
});

test('candidate keeps navigation, TLS, permission, and HTTP error guardrails', () => {
  assert.match(overlay, /TOP_LEVEL_HOSTS\.includes\(parsed\.hostname\.toLowerCase\(\)\)/);
  assert.match(overlay, /event\.request\.deny\(\)/);
  assert.match(overlay, /event\.handler\.handleCancel\(\)/);
  assert.match(overlay, /onHttpErrorReceive\(\(event\) =>/);
});
