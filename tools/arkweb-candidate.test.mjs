import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
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

test('candidate waits for Web attachment and proxy callback before navigation', () => {
  assert.match(overlay, /Web\(\{ src: 'about:blank'/);
  assert.match(overlay, /onControllerAttached\(\(\) =>/);
  assert.match(overlay, /applyProxyOverride\(config, \(\) =>/);
  assert.match(overlay, /config\.insertProxyRule\(rule\)/);
  assert.match(overlay, /this\.controller\.loadUrl\(HOME_URL\)/);
  assert.match(overlay, /setTimeout\(\(\) =>/);
  assert.match(overlay, /this\.controller\.stop\(\)/);
  assert.match(overlay, /private proxyAttempt: number = 0/);
  assert.match(overlay, /等待代理应用超时/);
  assert.match(overlay, /attempt !== this\.proxyAttempt/);
});

test('candidate keeps navigation, TLS, permission, and HTTP error guardrails', () => {
  assert.match(overlay, /TOP_LEVEL_HOSTS\.includes\(parsed\.hostname\.toLowerCase\(\)\)/);
  assert.match(overlay, /event\.request\.deny\(\)/);
  assert.match(overlay, /event\.handler\.handleCancel\(\)/);
  assert.match(overlay, /onHttpErrorReceive\(\(event\) =>/);
});
