import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../app/entry/src/main/ets/components/ReadingTabs.ets', import.meta.url), 'utf8');

// These checks protect the ArkUI source contract; Node does not render HdsTabs or run a screen reader.
test('all four system tabs supply their native names and disable tab-switch animation', () => {
  assert.match(source, /BottomTabBarStyle\.of\(symbol,\s*label\)\.id\(id\)/);
  assert.deepEqual(
    [...source.matchAll(/\.tabBar\(tabItem\('([^']+)',\s*'([^']+)'/g)].map(([, id, label]) => [id, label]),
    [['nav-home', '首页'], ['nav-search', '搜索'], ['nav-activity', '动态'], ['nav-profile', '我的']],
  );
  assert.match(source, /\.animationDuration\(0\)/);
});

test('the narrow mini bar and wide rail reuse one named compose button with an inward keyboard focus ring', () => {
  assert.match(source, /miniBarBuilder:\s*\(\)\s*=>\s*this\.ComposeAction\(\)/);
  assert.match(source, /if\s*\(this\.wide\)\s*\{\s*Row\(\)\s*\{\s*this\.ComposeAction\(\)/);
  const compose = source.match(/^  ComposeAction\(\) \{([\s\S]*?)^  \}/m)?.[1];
  assert.ok(compose, 'shared compose builder');
  assert.match(compose, /Button\(\{[^}]*\}\)\s*\{[^}]*\.accessibilityLevel\('no'\)[^}]*\}/);
  assert.match(compose, /\.id\('nav-compose'\)\.width\(48\)\.height\(48\)/);
  assert.match(compose, /\.focusable\(true\)\s*\.focusBox\(\{\s*margin:\s*LengthMetrics\.vp\(-2\),\s*strokeColor:\s*ColorMetrics\.resourceColor\(\$r\('app\.color\.timeline_text_primary'\)\),\s*strokeWidth:\s*LengthMetrics\.vp\(2\)\s*\}\)/);
  assert.match(compose, /\.accessibilityGroup\(true\)\.accessibilityText\('发帖'\)\.onClick\(\(\)\s*=>\s*this\.onCompose\(\)\)/);
});
