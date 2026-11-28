import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import { test } from 'node:test';

const overlay = readFileSync(new URL('../overlay/entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const app = readFileSync(new URL('../app/entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const timelineSource = readFileSync(new URL('../app/entry/src/main/ets/pages/Timeline.ets', import.meta.url), 'utf8');
const settingsSource = readFileSync(new URL('../app/entry/src/main/ets/components/SettingsPane.ets', import.meta.url), 'utf8');
const tabsSource = readFileSync(new URL('../app/entry/src/main/ets/components/ReadingTabs.ets', import.meta.url), 'utf8');
const profileSource = readFileSync(new URL('../app/entry/src/main/ets/components/LibraryHub.ets', import.meta.url), 'utf8');
const librarySource = readFileSync(new URL('../app/entry/src/main/ets/model/LocalLibrary.ets', import.meta.url), 'utf8');
const libraryModel = await import(`data:text/javascript,${encodeURIComponent(stripTypeScriptTypes(librarySource))}`);
const identitySource = readFileSync(new URL('../app/entry/src/main/ets/model/LocalIdentity.ets', import.meta.url), 'utf8');
const identityModel = await import(`data:text/javascript,${encodeURIComponent(stripTypeScriptTypes(identitySource))}`);

function timelineMethods(start, end) {
  const first = timelineSource.indexOf(start);
  const last = timelineSource.indexOf(end, first + start.length);
  assert.ok(first >= 0 && last > first, `cannot extract Timeline methods between ${start} and ${end}`);
  return timelineSource.slice(first, last).replace(/^  private (?:readonly )?/gm, '  ');
}

// Scope source-level wiring checks to the ArkUI builder that renders the control.
function builder(source, name) {
  const match = source.match(new RegExp(`^  ${name}\\([^\\n]*\\) \\{(?:[^\\n]*\\}$|[\\s\\S]*?^  \\})`, 'm'));
  assert.ok(match, `missing ArkUI builder: ${name}`);
  return match[0];
}

const nextSelection = timelineMethods('  private nextSelection(', '  private async toggleSaved(');
const appConfig = JSON.parse(readFileSync(new URL('../app/AppScope/app.json5', import.meta.url), 'utf8'));
const buildConfig = JSON.parse(readFileSync(new URL('../app/build-profile.json5', import.meta.url), 'utf8'));
const colors = JSON.parse(readFileSync(new URL('../app/entry/src/main/resources/base/element/color.json', import.meta.url), 'utf8'));
const darkColors = JSON.parse(readFileSync(new URL('../app/entry/src/main/resources/dark/element/color.json', import.meta.url), 'utf8'));
const fontConfig = JSON.parse(readFileSync(new URL('../app/AppScope/resources/base/profile/configuration.json', import.meta.url), 'utf8'));
const themeColors = (list) => Object.fromEntries(list.color.map((entry) => [entry.name, entry.value]));

function luminance(hex) {
  assert.match(hex, /^#[0-9A-F]{6}$/i);
  const rgb = hex.slice(1).match(/../g).map((channel) => {
    const srgb = Number.parseInt(channel, 16) / 255;
    return srgb <= 0.04045 ? srgb / 12.92 : ((srgb + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2];
}

test('ArkWeb source remains the reviewed proxy implementation and Stage keeps it as a page', () => {
  assert.match(overlay, /private changeProxy\(/);
  assert.match(app, /private changeProxy\(/);
  assert.match(app, /if \(Number\(router\.getLength\(\)\) > 1\) \{\s+Button\('本地首页'/);
  assert.match(app, /accessibilityText\('返回本地模拟时间线'\)\.onClick\(\(\) => \{ router\.back\(\); \}\)/);
  const back = app.slice(app.indexOf('  private goBack('), app.indexOf('  @Builder'));
  assert.match(back, /this\.canNavigate\(\)[\s\S]*?this\.controller\.accessBackward\(\)[\s\S]*?this\.controller\.backward\(\)[\s\S]*?router\.back\(\)/);
  assert.match(back, /if \(Number\(router\.getLength\(\)\) > 1\) \{\s+router\.back\(\);\s+return true;/);
  assert.doesNotMatch(app, /router\.pushUrl/);
  assert.equal(app, overlay, 'Stage ArkWeb page must remain synchronized with overlay source');
});

test('back closes settings, then prefers web history, then falls back to the timeline', () => {
  const methods = app.slice(app.indexOf('  private goBack('), app.indexOf('  @Builder'))
    .replace('private goBack', 'goBack');
  let stackLength = 2;
  const calls = [];
  const Back = vm.runInNewContext(stripTypeScriptTypes(`class Back { ${methods} }; Back`), {
    router: { getLength: () => String(stackLength), back: () => calls.push('timeline') }
  });
  const page = new Back();
  page.showSettings = true;
  page.canNavigate = () => true;
  page.controller = { accessBackward: () => true, backward: () => calls.push('web') };
  assert.equal(page.onBackPress(), true);
  assert.equal(page.showSettings, false);
  assert.deepEqual(calls, []);
  assert.equal(page.onBackPress(), true);
  assert.deepEqual(calls, ['web']);
  page.controller.accessBackward = () => false;
  assert.equal(page.onBackPress(), true);
  page.controller.accessBackward = () => { throw new Error('detached'); };
  assert.equal(page.onBackPress(), true);
  page.canNavigate = () => false;
  page.controller.accessBackward = () => { calls.push('unexpected web history access'); return true; };
  assert.equal(page.onBackPress(), true);
  stackLength = 1;
  assert.equal(page.onBackPress(), false);
  assert.deepEqual(calls, ['web', 'timeline', 'timeline', 'timeline']);
});

test('native timeline is a separate mock-data page and does not replace the ArkWeb page', () => {
  const timeline = readFileSync(new URL('../app/entry/src/main/ets/pages/Timeline.ets', import.meta.url), 'utf8');
  const ability = readFileSync(new URL('../app/entry/src/main/ets/entryability/EntryAbility.ets', import.meta.url), 'utf8');
  const pages = JSON.parse(readFileSync(new URL('../app/entry/src/main/resources/base/profile/main_pages.json', import.meta.url), 'utf8'));
  assert.match(timeline, /const POSTS: MockPost\[\]/);
  assert.ok([timeline, settingsSource].some(source => source.includes('本机操作不会连接 Threads；使用真实账号请打开网页。')),
    'the app must explicitly distinguish local actions from real Threads accounts');
  assert.match(timeline, /router\.pushUrl\(\{ url: 'pages\/Index' \}\)/);
  assert.match(ability, /loadContent\('pages\/Timeline'\)/);
  assert.deepEqual(pages.src, ['pages/Index', 'pages/Timeline']);
});

test('like counters and per-post animation triggers follow interaction state', async () => {
  const methods = timelineMethods('  private allowsMotionFeedback(', '  private async toggleFollow(');
  const Timeline = vm.runInNewContext(stripTypeScriptTypes(`class Timeline {
    library = emptyLibrary(); followedIds = []; savedIds = [];
    async saveLibrary(value) { this.library = value; this.likedIds = value.likedIds; return true; }
    ${nextSelection}
    ${methods}
  }; Timeline`), { ...libraryModel });
  const page = new Timeline();
  page.timelinePosts = [{ id: 'p1' }, { id: 'p2' }];
  page.animationTriggers = [-1, -1];
  page.likedIds = [];
  page.reduceMotion = false;
  page.motionPreferenceReady = true;
  page.systemReducesMotion = false;
  assert.equal(page.animationTriggerFor('p1'), -1);
  await page.toggleLike('p1');
  assert.deepEqual(Array.from(page.likedIds), ['p1']);
  assert.deepEqual(Array.from(page.animationTriggers), [0, -1]);
  assert.equal(page.animationTriggerFor('p1'), 0);
  assert.equal(page.animationTriggerFor('p2'), -1);
  await page.toggleLike('p1');
  assert.deepEqual(Array.from(page.likedIds), []);
  assert.deepEqual(Array.from(page.animationTriggers), [-1, -1]);
  await page.toggleLike('p2');
  assert.deepEqual(Array.from(page.likedIds), ['p2']);
  assert.deepEqual(Array.from(page.animationTriggers), [-1, 0]);
  page.setReduceMotion(true);
  assert.deepEqual(Array.from(page.animationTriggers), [-1, -1]);
  await page.toggleLike('p1');
  assert.deepEqual(Array.from(page.likedIds), ['p2', 'p1']);
  assert.deepEqual(Array.from(page.animationTriggers), [-1, -1]);
  assert.equal(page.animationTriggerFor('unknown'), -1);
  page.setReduceMotion(false);
  assert.deepEqual(Array.from(page.animationTriggers), [-1, -1], 'restoring motion must not replay old feedback');
  await page.toggleLike('unknown');
  assert.deepEqual(Array.from(page.likedIds), ['p2', 'p1']);
  await page.toggleLike('p1');
  for (let i = 0; i < 20; i++) await page.toggleLike('p1');
  assert.deepEqual(Array.from(page.likedIds), ['p2'], 'an even number of completed toggles cancels cleanly');
  assert.deepEqual(Array.from(page.animationTriggers), [-1, -1]);
  await page.toggleLike('p1');
  await page.toggleLike('p2');
  await page.toggleLike('p2');
  assert.deepEqual(Array.from(page.animationTriggers), [0, 0]);
  assert.equal(page.animationTriggerFor('p1'), 0, 'liking another post must not change this trigger');

  assert.match(timelineSource, /\.symbolEffect\(new BounceSymbolEffect\(EffectScope\.WHOLE\), this\.animationTriggerFor\(post\.id\)\)/);
  assert.doesNotMatch(timelineSource, /animatedPostId|@State private notice: string/);
});

test('motion preference is loaded before animation, serialized to disk and independent of the system override', async () => {
  const methods = timelineMethods('  private watchingSystemMotion', '  private async toggleFollow(');
  let finishMotionRead;
  const motionRead = new Promise((resolve) => { finishMotionRead = resolve; });
  let disk = false;
  let pending = false;
  let failSave = false;
  let writes = 0;
  let subscribed;
  const accessibility = {
    isAnimationReduceEnabledSync: () => false,
    onAnimationReduceStateChange: (callback) => { subscribed = callback; },
    offAnimationReduceStateChange: (callback) => { assert.equal(callback, subscribed); subscribed = undefined; }
  };
  const preferences = {
    getPreferences: async (context, options) => {
      assert.equal(context, 'host');
      assert.equal(options.name, 'timeline_display');
      return {
        get: async (key, fallback) => {
          assert.equal(key, 'reduce_motion');
          assert.equal(fallback, false);
          await motionRead;
          return disk;
        },
        put: async (key, value) => { assert.equal(key, 'reduce_motion'); pending = value; writes++; },
        flush: async () => { if (failSave) throw new Error('storage unavailable'); disk = pending; }
      };
    }
  };
  const Timeline = vm.runInNewContext(stripTypeScriptTypes(`class Timeline {
    reduceMotion = false; systemReducesMotion = false; motionPreferenceReady = false; motionPreferenceSaving = false;
    motionPreferenceWarning = ''; likedIds = []; followedIds = []; savedIds = [];
    animationTriggers = [-1]; timelinePosts = POSTS; library = emptyLibrary();
    getUIContext() { return { getHostContext: () => 'host' }; }
    async loadLibrary() {}
    async loadIdentity() {}
    async saveLibrary(value) { this.library = value; this.likedIds = value.likedIds; return true; }
    ${nextSelection}
    ${methods}
  }; Timeline`), { POSTS: [{ id: 'p1' }], DISPLAY_PREFERENCES: 'timeline_display', REDUCE_MOTION_KEY: 'reduce_motion',
    preferences, accessibility, ...libraryModel });

  const page = new Timeline();
  page.aboutToAppear();
  await page.toggleLike('p1');
  assert.deepEqual(Array.from(page.likedIds), ['p1']);
  assert.equal(page.animationTriggerFor('p1'), -1, 'no bounce while preference is loading');
  finishMotionRead();
  await new Promise(setImmediate);
  assert.equal(page.allowsMotionFeedback(), true);
  const save = page.updateMotionPreference(true);
  assert.equal(page.allowsMotionFeedback(), false, 'suppress immediately, not after I/O');
  await page.updateMotionPreference(false);
  await save;
  assert.equal(disk, true);
  assert.equal(writes, 1, 'no competing writes');
  page.aboutToDisappear();
  assert.equal(subscribed, undefined);

  const restart = new Timeline();
  restart.aboutToAppear();
  await new Promise(setImmediate);
  assert.equal(restart.reduceMotion, true);
  await restart.toggleLike('p1');
  assert.equal(restart.animationTriggerFor('p1'), -1);
  assert.deepEqual(Array.from(restart.likedIds), ['p1']);
  subscribed(true);
  await restart.updateMotionPreference(false);
  assert.equal(disk, false);
  await restart.toggleLike('p1');
  await restart.toggleLike('p1');
  assert.equal(restart.animationTriggerFor('p1'), -1, 'system reduction overrides the local switch');
  subscribed(false);
  assert.equal(restart.animationTriggerFor('p1'), -1, 'no replay when the system setting is restored');
  await restart.toggleLike('p1');
  await restart.toggleLike('p1');
  assert.equal(restart.animationTriggerFor('p1'), 0);

  failSave = true;
  await restart.updateMotionPreference(true);
  assert.equal(restart.allowsMotionFeedback(), false);
  assert.equal(restart.motionPreferenceSaving, false);
  assert.match(restart.motionPreferenceWarning, /未能保存/);
  assert.equal(disk, false);
  restart.aboutToDisappear();
  assert.match(timelineSource, /if \(this\.allowsMotionFeedback\(\)\) \{\s+SymbolGlyph[\s\S]*?\.symbolEffect\([\s\S]*?\} else \{\s+SymbolGlyph[^}]*\}/);
});

test('the settings destination wires its switch to persisted preferences and still offers Back and web access', () => {
  const destination = builder(timelineSource, 'DetailDestination');
  assert.match(destination, /name === POST_SETTINGS[\s\S]*?NavDestination\(\)\s*\{\s*SettingsPane\(\{/);
  for (const prop of ['reduceMotion', 'systemReducesMotion', 'motionPreferenceReady', 'motionPreferenceSaving', 'motionPreferenceWarning']) {
    assert.ok(destination.includes(`${prop}: this.${prop}`), `settings must observe ${prop}`);
  }
  assert.match(destination, /onMotionChange:[^\n]*this\.updateMotionPreference\(enabled\)/);
  assert.match(destination, /onClose:[^\n]*this\.closePost\(\)/);
  assert.match(destination, /onWeb:[^\n]*this\.openWeb\(\)/);
  assert.match(settingsSource, /Toggle\(\{ type: ToggleType\.Switch, isOn: this\.reduceMotion \}\)[\s\S]*?\.enabled\(this\.motionPreferenceReady && !this\.motionPreferenceSaving\)[\s\S]*?\.onChange\([^\n]*this\.onMotionChange\(enabled\)/);
  assert.match(settingsSource, /\.onClick\([^\n]*this\.onClose\(\)/);
  assert.match(settingsSource, /\.onClick\([^\n]*this\.onWeb\(\)/);
  assert.doesNotMatch(timelineSource, /Toggle\(\{[^}]*isOn:\s*this\.reduceMotion/, 'do not maintain a second preference UI');
});

test('timeline color resources exist in both modes and readable pairings meet 4.5:1', () => {
  const timeline = readFileSync(new URL('../app/entry/src/main/ets/pages/Timeline.ets', import.meta.url), 'utf8');
  const light = themeColors(colors);
  const dark = themeColors(darkColors);
  assert.equal(Object.keys(light).length, colors.color.length);
  assert.equal(Object.keys(dark).length, darkColors.color.length);
  assert.deepEqual(Object.keys(dark).sort(), Object.keys(light).sort());
  assert.notEqual(light.timeline_background, dark.timeline_background);
  for (const [, name] of timeline.matchAll(/\$r\('app\.color\.(timeline_\w+)'\)/g)) {
    assert.ok(name in light, `missing timeline palette entry: ${name}`);
  }
  const pairs = [
    ['text_primary', 'background'], ['text_secondary', 'background'],
    ['text_primary', 'surface'], ['text_body', 'surface'], ['text_secondary', 'surface'],
    ['text_muted', 'surface'], ['text_muted', 'background'],
    ['text_body', 'toolbar_button'], ['on_action', 'action'],
    ['action_muted', 'surface_muted'], ['like', 'surface'],
  ];
  for (const [mode, palette] of Object.entries({ light, dark })) {
    for (const [foreground, background] of pairs) {
      const [a, b] = [foreground, background].map((role) => luminance(palette[`timeline_${role}`]));
      assert.ok((Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05) >= 4.5,
        `${mode}: ${foreground} on ${background} must meet 4.5:1`);
    }
  }
});

test('the home toolbar renders a two-way native feed filter without settings or web shortcuts', () => {
  const toolbar = builder(timelineSource, 'Toolbar');
  assert.match(toolbar, /Text\(['"]本机预览['"]\)/);
  assert.doesNotMatch(toolbar, /openSettings|openWeb|settingsVisible|router\./);
  assert.match(builder(timelineSource, 'ProfileRoot'), /LibraryHub\(\{[\s\S]*onSettings:[^\n]*this\.openSettings\(\)/,
    'settings must remain accessible from the profile');
  assert.match(builder(profileSource, 'Profile'), /Button\('设置'[^\n]*\.id\('library-settings'\)[\s\S]*?\.onClick\([^\n]*this\.onSettings\(\)/);

  const options = toolbar.match(/\bTabSegmentButtonV2\((\{[\s\S]*?\})\)/)?.[1];
  assert.ok(options, 'instantiate the system segment; custom buttons with the same labels are not a substitute');
  const segments = timelineSource.match(/(\w+)\s*:\s*SegmentButtonV2Items\s*=\s*new SegmentButtonV2Items\((\[[\s\S]*?\])\)/);
  assert.ok(segments, 'missing segment items');
  const makeOptions = vm.runInNewContext(stripTypeScriptTypes(`(function() {
    this.${segments[1]} = ${segments[2]}; return (${options});
  })`));
  const selected = [];
  const page = { followingOnly: false, selectFeed: following => selected.push(following) };
  const config = makeOptions.call(page);
  assert.deepEqual(Array.from(config.items, item => item.text), ['为你', '关注中']);
  assert.equal(config.selectedIndex, 0);
  page.followingOnly = true;
  assert.equal(makeOptions.call(page).selectedIndex, 1);
  config.$selectedIndex(1);
  config.$selectedIndex(0);
  assert.deepEqual(selected, [true, false]);
});

test('the flat reading rows still expose follow, like, replies and bookmark actions', () => {
  const row = builder(timelineSource, 'PostCard');
  assert.match(row, /Divider\(\)/);
  assert.doesNotMatch(row, /\.shadow\(/);
  assert.match(row, /this\.FollowAction\(post\)/);
  assert.match(row, /this\.PostActions\(post, inDetail\)/);
  assert.match(row, /Text\(post\.body\.trim\(\) \? post\.body : \(post\.video !== undefined \? '视频帖子' : '图片帖子'\)\)\s*\.id\('body-' \+ post\.id\)[^{}]*?\.onClick\(\(\) => this\.openPost\(post\)\)/,
    'the feed body opens the original post, not a selected reply');
  assert.match(row, /if \(!inDetail\)\s*\{\s*ForEach\(this\.previewRows\(post\.id\),[\s\S]*?this\.SummaryEntry\(post, reply\)[\s\S]*?=> reply\.id\)/,
    'replace only the summary row and tap handler when the latest reply ID changes');
  const summary = builder(timelineSource, 'SummaryEntry');
  assert.match(summary, /Text\(reply\.author \+ '：' \+ reply\.body\)/);
  assert.match(summary, /\.id\('summary-' \+ post\.id\)[^{}]*?\.onClick\(\(\) => this\.openPost\(post, reply\.id\)\)/,
    'the summary opens the specific reply shown on that same post');
  const actions = builder(timelineSource, 'PostActions');
  for (const handler of ['toggleLike(post.id)', 'openPost(post)', 'toggleSaved(post)']) {
    assert.ok(actions.includes(`this.${handler}`), `missing post action: ${handler}`);
  }
  assert.match(builder(timelineSource, 'FollowAction'), /\.onClick\([^\n]*this\.toggleFollow\(post\.id\)/);
});

test('post overflow uses an anchored native menu with only local actions', () => {
  assert.match(builder(timelineSource, 'PostActions'), /\.bindMenu\(this\.PostMenu\(post\)\)/);
  const menu = builder(timelineSource, 'PostMenu');
  assert.match(menu, /Menu\(\)\s*\{/);
  for (const [label, action] of [['复制正文', 'copyPost(post)'], ['分享正文…', 'sharePost(post)'],
    ['编辑本机帖子', 'openPostEditor(post)'], ['隐藏此示例', 'toggleHidden(post.id)']]) {
    assert.ok(menu.includes(label) && menu.includes(`this.${action}`));
  }
  assert.match(menu, /if \(post\.local\) \{[\s\S]*?this\.openPostEditor\(post\)[\s\S]*?\} else \{[\s\S]*?this\.toggleHidden\(post\.id\)/);
  const actions = timelineMethods('  private async copyPost(', '  @Builder\n  PostMenu(');
  assert.match(actions, /setData\(pasteboard\.createData\(pasteboard\.MIMETYPE_TEXT_PLAIN, this\.threadText\(post\)\)\)/);
  assert.match(actions, /SharedData\(\{ utd: 'general\.plain-text', content: this\.threadText\(post\)/);
  assert.doesNotMatch(actions, /https?:|\.openLink\(/);
});

test('Stage follows system font scale and timeline reflows when text grows', () => {
  const timeline = readFileSync(new URL('../app/entry/src/main/ets/pages/Timeline.ets', import.meta.url), 'utf8');
  assert.equal(appConfig.app.configuration, '$profile:configuration');
  assert.deepEqual(fontConfig.configuration, { fontSizeScale: 'followSystem', fontSizeMaxScale: '3.2' });
  const ability = readFileSync(new URL('../app/entry/src/main/ets/entryability/EntryAbility.ets', import.meta.url), 'utf8');
  assert.match(ability, /onConfigurationUpdate\(config: Configuration\)[\s\S]*AppStorage\.setOrCreate\('timelineFontScale', config\.fontSizeScale/);
  assert.match(ability, /this\.onConfigurationUpdate\(this\.context\.config\);\s+windowStage\.loadContent\('pages\/Timeline'\)/);
  assert.match(timeline, /@StorageProp\('timelineFontScale'\)/);
  const feed = builder(timeline, 'Feed');
  assert.match(feed, /\.lanes\(this\.readingLaneCount\(\)/);
  assert.match(feed, /if \(!this\.toolbarInList\(\)\)\s*\{\s*this\.Toolbar\(\)/);
  assert.match(feed, /if \(this\.toolbarInList\(\)\)\s*\{\s*ListItem\(\)\s*\{\s*this\.Toolbar\(\)/);
  assert.doesNotMatch(timeline, /Text\(post\.body\)[^\n]*(?:lineHeight|maxLines)/);
});

test('reading reflow keeps a post ID, adjusts for the large-text toolbar and defers while hidden', () => {
  const timeline = readFileSync(new URL('../app/entry/src/main/ets/pages/Timeline.ets', import.meta.url), 'utf8');
  const methods = timeline.slice(timeline.indexOf('  onPageShow('), timeline.indexOf('  private async displayPreferences('))
    .replace(/^  private /gm, '  ');
  const frames = [];
  const calls = [];
  let offset = 310;
  let rect = { height: 120, y: -28 };
  const Timeline = vm.runInNewContext(stripTypeScriptTypes(`class Timeline {
    timelineVisible = true; restorePending = false; restoreScheduled = false;
    viewportWidth = 400; fontScale = 1; firstVisibleIndex = 1; timelinePosts = POSTS;
    selectedTab = ShellTab.Home; followingOnly = false; followedIds = ['p2']; hiddenIds = [];
    followingTabAnchor = { postId: '', clipped: 0 };
    detailPaths = { size: () => 0 };
    ${timelineMethods('  private visibleFeed(', '  private activityEntries(')}
    getUIContext() { return { postFrameCallback: (frame) => frames.push(frame) }; }
    ${methods}
  }; Timeline`), {
    POSTS: [{ id: 'p1' }, { id: 'p2' }, { id: 'p3' }], LARGE_TEXT_SCALE: 1.4, WIDE_VIEWPORT: 680, ShellTab: { Home: 0 },
    LayoutFrame: class { constructor(task) { this.task = task; } }, frames,
    ScrollAlign: { START: 'start' }, LengthMetrics: { vp: (n) => n }
  });
  const page = new Timeline();
  page.timelineScroller = {
    offset: () => ({ yOffset: offset }),
    getItemRect: () => rect,
    scrollToIndex: (...args) => calls.push(args)
  };
  page.rememberReadingPosition();
  assert.equal(page.readingAnchor.postId, 'p2');
  assert.equal(page.readingAnchor.clipped, 28);
  page.viewportWidth = 820;
  assert.equal(page.readingLaneCount(), 2);
  page.contentWidth = 400;
  assert.equal(page.readingLaneCount(), 1, 'a narrow content pane on a wide window must still use one lane');
  page.contentWidth = 820;
  page.onReadingLayoutChange();
  page.onReadingLayoutChange();
  assert.equal(frames.length, 1, 'coalesce several layout changes into one frame');
  page.firstVisibleIndex = 0;
  page.rememberReadingPosition();
  assert.equal(page.readingAnchor.postId, 'p2', 'reflow must not overwrite the old anchor');
  rect = { height: 0, y: 0 };
  frames.shift().task();
  const offscreen = calls.shift();
  assert.deepEqual(offscreen.slice(0, 3), [1, false, 'start']);
  assert.ok(offscreen[3].extraOffset === 0);

  page.onPageHide();
  page.fontScale = 2;
  page.onReadingLayoutChange();
  assert.equal(page.readingLaneCount(), 1);
  assert.equal(frames.length, 0);
  page.onPageShow();
  rect = { height: 40, y: 25 };
  frames.shift().task();
  const [index, animated, align, options] = calls.shift();
  assert.deepEqual([index, animated, align, options.extraOffset], [2, false, 'start', 20]);
  page.onPageHide();
  page.onPageShow();
  assert.equal(frames.length, 0, 'return without a layout change leaves the native scroll position alone');

  page.firstVisibleIndex = 0;
  offset = 0;
  page.rememberReadingPosition();
  offset = 50;
  page.onReadingLayoutChange();
  frames.shift().task();
  assert.deepEqual(calls.shift(), [0, false, 'start']);
  assert.equal(page.restorePending, false);

  page.fontScale = 1;
  page.timelinePosts = [{ id: 'preview-1' }, ...page.timelinePosts];
  page.firstVisibleIndex = 2;
  rect = { height: 120, y: -28 };
  page.rememberReadingPosition();
  assert.equal(page.readingAnchor.postId, 'p2', 'local posts count towards the visible index');
  page.fontScale = 2;
  page.onReadingLayoutChange();
  rect = { height: 0, y: 0 };
  frames.shift().task();
  assert.deepEqual(calls.shift().slice(0, 3), [3, false, 'start']);

  // Each filter remembers its own post and clipped offset, even with a scrolling large-text header.
  rect = { height: 120, y: -28 };
  page.firstVisibleIndex = 3;
  page.selectFeed(true);
  frames.shift().task();
  assert.deepEqual(calls.shift(), [0, false, 'start']);
  assert.deepEqual(Array.from(page.visibleFeed(), post => post.id), ['p2']);
  page.firstVisibleIndex = 1;
  rect = { height: 120, y: -9 };
  page.selectFeed(false);
  frames.shift().task();
  const restoredHome = calls.shift();
  assert.deepEqual([restoredHome[0], restoredHome[3].extraOffset], [3, 28]);
  page.firstVisibleIndex = 3;
  rect = { height: 120, y: -28 };
  page.selectFeed(true);
  frames.shift().task();
  const restoredFollowing = calls.shift();
  assert.deepEqual([restoredFollowing[0], restoredFollowing[3].extraOffset], [1, 9]);
});

test('UIDesignKit HdsTabs hosts four native tab bars; compose is an action, not a fifth destination', () => {
  assert.match(tabsSource, /import\s*\{[^}]*\bHdsTabs\b[^}]*\}\s*from\s*['"]@kit\.UIDesignKit['"]/);
  const build = builder(tabsSource, 'build');
  const children = build.match(/^(\s*)HdsTabs\(\{\s*index:\s*this\.activeIndex\s*\}\)\s*\{([\s\S]*?)^\1\}/m)?.[2];
  assert.ok(children, 'instantiate HdsTabs controlled by the parent tab index');
  const pages = [...children.matchAll(/TabContent\(\)\s*\{([\s\S]*?)\}\.tabBar\((\w+)\(/g)];
  assert.equal(children.match(/\bTabContent\(/g)?.length, 4);
  assert.deepEqual(pages.map(([, content]) => content.match(/this\.(home|search|activity|profile)\(\)/)?.[1]),
    ['home', 'search', 'activity', 'profile']);
  for (const factory of new Set(pages.map(([, , name]) => name))) {
    assert.match(tabsSource, new RegExp(`function ${factory}\\([^}]+\\{[\\s\\S]*?return BottomTabBarStyle\\.of\\(`));
  }
  assert.doesNotMatch(children, /this\.(?:onCompose|ComposeAction)\(/);
  assert.match(build, /\.onChange\([\s\S]*?this\.onSelectTab\(index\)/);
  assert.match(build.replace(children, ''), /this\.ComposeAction\(\)/);
  assert.match(builder(tabsSource, 'ComposeAction'), /Button\([\s\S]*?\.onClick\([^\n]*this\.onCompose\(\)/);
});

test('the parent wires the four reading pages and the independent composer to the real tab shell', () => {
  const options = builder(timelineSource, 'Shell').match(/\bReadingTabs\((\{[\s\S]*?\})\)/)?.[1];
  assert.ok(options, 'the timeline must instantiate ReadingTabs, not just import it');
  const visits = [];
  let discovery;
  let profile;
  const topics = ['主题'];
  const shell = vm.runInNewContext(stripTypeScriptTypes(`class Shell {
    selectedTab = 2; sideNavigation = false; searchQuery = '初始'; discoveryMode = 1; libraryMode = 0;
    identity = { name: '本机名称', bio: '' }; localReplies = []; libraryLoading = false; libraryReady = true;
    libraryBusy = false; identityBusy = false;
    loadLibrary() { visits.push('retry library'); }
    identityMessage = ''; libraryMessage = '';
    Feed() { visits.push('home'); } activityEntries() { return ['activity']; }
    discoveryAuthors() { return ['author']; } discoveryPosts() { return ['post']; }
    DiscoveryPostRows() { visits.push('search rows'); } LibraryStatus() { visits.push('library status'); }
    profilePosts() { return ['post']; } ProfileItems() { visits.push('profile rows'); }
    selectTab(index) { visits.push(index); } openComposer() { visits.push('compose'); }
    openAuthor(id) { visits.push(id); } openIdentity() { visits.push('edit identity'); }
    openSettings() { visits.push('settings'); } openWeb() { visits.push('web'); }
    ${builder(timelineSource, 'SearchRoot')}
    ${builder(timelineSource, 'ActivityRoot')}
    ${builder(timelineSource, 'ProfileRoot')}
    options() { return (${options}); }
  }; new Shell()`), {
    visits, SIDE_NAV_WIDTH: 840, DISCOVERY_TOPICS: topics,
    DiscoveryPane: (props) => { visits.push('search'); discovery = props; },
    ActivityPane: ({ entries }) => visits.push(...entries),
    LibraryHub: (props) => { visits.push('profile'); profile = props; }
  });
  const config = shell.options();
  assert.equal(config.activeIndex, shell.selectedTab);
  for (const slot of ['home', 'search', 'activity', 'profile']) config[slot]();
  config.onSelectTab(3);
  config.onCompose();
  assert.deepEqual(visits, ['home', 'search', 'activity', 'profile', 3, 'compose']);
  assert.equal(discovery.query, '初始');
  assert.equal(discovery.mode, 1);
  assert.equal(discovery.topics, topics);
  assert.equal(discovery.hasPosts, true);
  discovery.onQuery('搜索');
  assert.equal(shell.searchQuery, '搜索');
  discovery.onTopic(topics[0]);
  assert.equal(shell.searchQuery, topics[0]);
  assert.equal(shell.discoveryMode, 0);
  discovery.posts();
  discovery.status();
  discovery.onAuthor('author');
  assert.equal(profile.identity, shell.identity);
  assert.equal(profile.hasItems, true);
  profile.items();
  profile.onMode(3);
  config.profile();
  assert.equal(profile.mode, 3);
  assert.equal(profile.hasItems, false, 'reply mode reads replies, not the matching posts');
  profile.onEdit();
  profile.onCompose();
  profile.onSettings();
  profile.onWeb();
  assert.deepEqual(visits.slice(6), ['search rows', 'library status', 'author', 'profile rows', 'profile',
    'edit identity', 'compose', 'settings', 'web']);
});

test('shell tabs and local activity preserve origin and never create duplicate routes', () => {
  const lifecycle = timelineMethods('  onPageShow(', '  private async displayPreferences(');
  const actions = timelineMethods('  private selectTab(', '  private authorSummary(');
  const tabs = { Home: 0, Search: 1, Activity: 2, Profile: 3 };
  const Shell = vm.runInNewContext(stripTypeScriptTypes(`class Shell {
    selectedTab = ShellTab.Home; timelineVisible = true;
    timelinePosts = [{id:'p1',name:'first',handle:'@first',body:'hello'},{id:'p2',name:'second',handle:'@second',body:'world'}];
    likedIds = ['p1','missing']; savedIds = ['p1']; followedIds = ['p2']; hiddenIds = [];
    localReplies = [{id:'r1',postId:'p2',body:'reply'},{id:'r2',postId:'missing',body:'ignore'}];
    stack = []; motion = false; opened = [];
    detailPaths = { size: () => this.stack.length, pushPath: (entry) => this.stack.push(entry) };
    readingAnchor = { postId:'p1',clipped:15 }; homeTabAnchor = {postId:'',clipped:0};
    followingTabAnchor = {postId:'',clipped:0}; followingOnly = false;
    allowsMotionFeedback() { return this.motion; }
    getUIContext() { return { postFrameCallback() {} }; }
    openPost(post, focusId) { this.opened.push([post.id, focusId]); }
    ${lifecycle}
    ${actions}
    ${timelineMethods('  private currentPostBody(', '  private async copyPost(')}
  }; Shell`), { ShellTab: tabs, POST_SETTINGS: 'Settings', LayoutFrame: class {}, matchesPost: libraryModel.matchesPost });
  const page = new Shell();
  page.selectFeed(true);
  assert.deepEqual(Array.from(page.visibleFeed(), (post) => post.id), ['p2']);
  assert.equal(page.readingAnchor.postId, '');
  page.selectFeed(false);
  assert.equal(page.readingAnchor.postId, 'p1');
  page.searchQuery = 'kept query';
  page.selectTab(tabs.Search);
  assert.equal(page.searchQuery, 'kept query');
  assert.equal(page.timelineVisible, false);
  assert.equal(page.onBackPress(), true);
  assert.equal(page.selectedTab, tabs.Home);
  page.selectTab(tabs.Profile);
  page.openSettings();
  page.openSettings();
  page.selectTab(tabs.Search);
  assert.equal(page.stack.length, 1);
  assert.equal(page.selectedTab, tabs.Profile);
  assert.equal(page.onBackPress(), false, 'the destination owns Back while on the stack');
  page.stack.pop().onPop();
  assert.equal(page.selectedTab, tabs.Profile);
  assert.equal(page.onBackPress(), true);
  assert.equal(page.timelineVisible, true);
  assert.equal(page.onBackPress(), false);
  const entries = page.activityEntries();
  assert.deepEqual(Array.from(entries, ({ id }) => id), ['like-p1', 'save-p1', 'reply-r1']);
  page.openActivityPost(entries[2]);
  page.openActivityPost({ postId: 'missing' });
  assert.deepEqual(Array.from(page.opened, (entry) => Array.from(entry)), [['p2', 'r1']]);
  page.searchQuery = 'world';
  assert.deepEqual(Array.from(page.discoveryPosts(), ({ id }) => id), ['p2']);
  page.hiddenIds = ['p2'];
  assert.deepEqual(Array.from(page.discoveryPosts(), ({ id }) => id), []);
  assert.deepEqual(Array.from(page.visibleFeed(), ({ id }) => id), ['p1']);
});

test('post detail uses one stack entry and saves replies only to the local library for that post', async () => {
  const methods = timelineMethods('  private openPost(', '  private nextSelection(');
  const post = { id: 'p1', name: 'first', replies: 12 };
  const other = { id: 'p2', name: 'second', replies: 7 };
  let disk = '';
  let pending = '';
  let failFlush = false;
  let flushGate;
  let writes = 0;
  const store = {
    async get(key, fallback) { assert.equal(key, 'content_v1'); assert.equal(fallback, ''); return disk; },
    async put(key, data) { assert.equal(key, 'content_v1'); pending = data; writes++; },
    async flush() {
      if (flushGate) await flushGate;
      if (failFlush) throw new Error('library write failed');
      disk = pending;
    }
  };
  const Timeline = vm.runInNewContext(stripTypeScriptTypes(`class Timeline {
    timelineVisible = true; replyDraft = 'old draft'; replySequence = 0; localReplies = [];
    motion = false; anchorCaptures = 0; timelinePosts = POSTS; animationTriggers = [-1, -1];
    library = emptyLibrary(); libraryReady = false; libraryBusy = false; libraryLoading = false; identity = emptyIdentity();
    allowsMotionFeedback() { return this.motion; }
    rememberReadingPosition() { this.anchorCaptures++; }
    onPageShow() { this.timelineVisible = this.detailPaths.size() === 0; }
    getUIContext() { return { getHostContext: () => 'host' }; }
    inform() {}
    ${methods}
  }; Timeline`), {
    ...libraryModel, ...identityModel, POSTS: [post, other], POST_DETAIL: 'PostDetail', AUTHOR_PROFILE: 'AuthorProfile',
    LIBRARY_STORE: 'timeline_local_library', LIBRARY_KEY: 'content_v1', REPLY_LIMIT: 280,
    SAMPLE_REPLIES: [{ id: 's1', postId: 'p1', body: 'sample' }],
    preferences: { getPreferences: async (context, { name }) => {
      assert.equal(context, 'host');
      assert.equal(name, 'timeline_local_library');
      return store;
    } }
  });
  const page = new Timeline();
  await page.loadLibrary();
  assert.equal(page.libraryReady, true);
  const stack = [];
  const transitions = [];
  page.detailPaths = {
    size: () => stack.length,
    getAllPathName: () => stack.map(({ name }) => name),
    pushPath: (entry, animated) => { stack.push(entry); transitions.push(animated); },
    pop: (result, animated) => { transitions.push(animated); stack.pop().onPop(result); }
  };
  page.openPost(post);
  page.openPost(other);
  assert.equal(stack.length, 1);
  assert.equal(stack[0].param.id, 'p1');
  assert.equal(page.anchorCaptures, 1);
  assert.equal(page.timelineVisible, false);
  assert.equal(page.replyDraft, '');
  assert.equal(page.replyCount(post), 12);
  page.beginReply(post.id, 's1');
  for (const draft of [' \n ', 'a'.repeat(281)]) {
    page.replyDraft = draft;
    await page.submitReply('p1');
  }
  const draft = '  第一条本地回复  ';
  page.replyDraft = draft;
  await page.submitReply('missing');
  assert.equal(writes, 0);
  assert.equal(page.localReplies.length, 0);
  failFlush = true;
  await page.submitReply('p1');
  assert.equal(page.replyDraft, draft);
  assert.equal(page.replyTargetId, 's1');
  assert.equal(page.focusedReplyId, '');
  assert.equal(page.replyCount(post), 12);
  assert.match(page.libraryMessage, /未能保存/);
  failFlush = false;
  let releaseFlush;
  flushGate = new Promise((resolve) => { releaseFlush = resolve; });
  const saving = page.submitReply('p1');
  await page.submitReply('p1');
  assert.equal(page.libraryBusy, true);
  assert.equal(page.replyDraft, draft);
  assert.equal(page.focusedReplyId, '');
  assert.equal(disk, '');
  releaseFlush();
  await saving;
  assert.equal(writes, 2, 'one failed save and one successful save, with no concurrent double send');
  assert.equal(page.replyDraft, '');
  assert.equal(page.focusedReplyId, 'local-1');
  assert.equal(page.replyCount(post), 13);
  assert.equal(page.replyCount(other), 7);
  assert.deepEqual(Array.from(page.repliesFor('p1'), (reply) => reply.body), ['sample', '第一条本地回复'],
    'a nested local reply appears after its parent');
  assert.equal(page.repliesFor('p2').length, 0);
  page.expandCurrentReply(post.id);
  page.replyDraft = '未提交的草稿';
  page.requestDetailBack();
  assert.equal(page.replyExitPending, true);
  assert.equal(stack.length, 1, 'Back must not silently lose a reply draft');
  page.discardReplyAndClose();
  page.requestDetailBack();
  assert.equal(page.replyDraft, '');
  assert.equal(page.timelineVisible, true);
  page.motion = true;
  page.openPost(other);
  page.closePost();
  assert.deepEqual(transitions, [false, false, true, true]);
  assert.equal(page.replyCount(post), 13);
  const reopened = new Timeline();
  assert.equal(reopened.replyCount(post), 12, 'before loading the local library only public demo counts are visible');
  await reopened.loadLibrary();
  assert.equal(reopened.replyCount(post), 13, 'local replies survive a fresh page after loading device preferences');
  assert.equal(reopened.replySequence, 1);
  assert.equal(reopened.repliesFor('p1')[1].parentId, 's1');
  assert.equal(reopened.repliesFor('p2').length, 0);
  stack.push({ name: 'Settings' });
  page.openPost(post);
  assert.deepEqual(stack.map(({ name }) => name), ['Settings'], 'details cannot open through settings');
  stack.pop();
  stack.push({ name: 'AuthorProfile' });
  page.openPost(post, 'local-1');
  page.openPost(other);
  assert.deepEqual(stack.map(({ name }) => name), ['AuthorProfile', 'PostDetail']);
  assert.equal(page.focusedReplyId, 'local-1');
  page.closePost();
  assert.deepEqual(stack.map(({ name }) => name), ['AuthorProfile'], 'closing detail returns to the same author');
  assert.match(timelineSource, /Navigation\(this\.detailPaths\)/);
  const detail = builder(timelineSource, 'DetailDestination');
  assert.match(detail, /this\.DetailContent\(post\)[\s\S]*?\.onBackPressed\(\(\) => \{\s*this\.requestDetailBack\(\);\s*return true;/);
  assert.match(detail, /name === IDENTITY_EDITOR[\s\S]*?IdentityEditor\(\{[\s\S]*?onBack: \(\) => this\.requestIdentityBack\(\)/);
  assert.match(detail, /name === POST_EDITOR[\s\S]*?this\.PostEditorContent\(\)[\s\S]*?\.onBackPressed\(\(\) => \{ this\.requestPostEditorBack\(\); return true;/);
  assert.match(detail, /name === AUTHOR_PROFILE && post !== undefined[\s\S]*?AuthorPane\(\{ author: this\.authorSummary\(post\.id\)/);
  assert.match(builder(timelineSource, 'DiscussionRoot'), /this\.PostCard\(post, true, false, this\.currentContinuation\(post\)\.length > 0\)/);
  const original = builder(timelineSource, 'PostCard');
  assert.match(original, /if \(inDetail && !completeThread\) \{\s*if \(this\.currentPostBody\(post\)\.trim\(\)\.length > 0\) \{\s*Text\(this\.currentPostBody\(post\)\)/,
    'detail renders the current local post rather than its navigation snapshot');
  assert.match(original, /this\.ThreadPartContent\(this\.makePart\(this\.currentPostBody\(post\), this\.currentPhotoKeys\(post\),\s*this\.currentVideo\(post\)\), 1,/,
    'the first thread segment reads current content and attachments too');
  assert.match(builder(timelineSource, 'Feed'), /this\.PostCard\(post, false\)/);
});

test('composer and preview keep primary actions outside scrolling, with shared thread rows and guarded exit', () => {
  const editor = builder(timelineSource, 'ComposerContent');
  const preview = builder(timelineSource, 'PostPreviewContent');
  assert.match(editor, /\.layoutWeight\(1\)\.align\(Alignment\.Top\)\.scrollBar\(BarState\.Auto\)\s+\.onAppear\(\(\) => this\.restoreComposerOffset\(\)\)\s+if \(this\.postDraftReady\) \{ this\.ComposerFooter\(\) \}/);
  assert.match(preview, /\.layoutWeight\(1\)\.align\(Alignment\.Top\)\.scrollBar\(BarState\.Auto\)[\s\S]*'composer-preview-confirm'/);
  assert.match(preview, /this\.makePart\(this\.previewBody, this\.previewPhotoKeys, this\.previewVideo\)[\s\S]*ForEach\(this\.previewContinuation/);
  assert.match(builder(timelineSource, 'ComposerFooter'), /this\.draftDecision !== DraftDecision\.None[\s\S]*this\.ComposerDecision\(\)[\s\S]*this\.ComposerActions\(\)[\s\S]*maxHeight: this\.composerActionHeight\(\)/);
  assert.match(builder(timelineSource, 'ComposerActions'), /this\.canSavePostDraft\(\)[\s\S]*this\.canPreviewPostDraft\(\)/);
  assert.match(editor, /ForEach\(\[this\.composerInputVersion\][\s\S]*this\.updateComposerInput\(version, value\)/);
  assert.match(builder(timelineSource, 'DetailDestination'), /\.onWillShow\(\(\) => this\.setComposerKeyboard\(true\)\)\s+\.onWillHide\(\(\) => this\.setComposerKeyboard\(false\)\)/);
  assert.match(builder(timelineSource, 'ComposerHeading'), /this\.requestComposerExit\(\)/);
});

test('post drafts persist explicitly and preview posts are added once without modifying the saved draft', async () => {
  const constants = timelineSource.slice(timelineSource.indexOf('const POST_DETAIL'), timelineSource.indexOf('interface DemoReply'));
  const methods = [timelineMethods('  private localPost(', '  @Builder\n  PostMenu('),
    timelineMethods('  private async postDraftPreferences(', '  @Builder')].join('\n');
  const { Composer, DraftDecision, ShellTab } = vm.runInNewContext(stripTypeScriptTypes(`
    ${constants}
    class Composer {
      postDraft = ''; savedPostDraft = ''; postDraftReady = false; postDraftBusy = false;
      postDraftMessage = ''; draftDecision = DraftDecision.None; postDraftLoadId = 0;
      showingPostPreview = false; previewBody = ''; postSequence = 0;
      draftPhotoKeys = []; savedDraftPhotoKeys = []; previewPhotoKeys = []; viewerPhotoKeys = []; viewerPhotoIndex = 0;
      draftParts = [{ body: '' }]; activeDraftPart = 0; savedContinuation = []; previewContinuation = [];
      photoPicking = false;
      composerInputVersion = 0; composerHeight = 0; viewportWidth = 0; fontScale = 1;
      composerVisible = false; composerKeyboardMode = undefined; previewReturnOffset = -1;
      inputStops = 0; scrollY = 0; frames = []; keyboardMode = KeyboardAvoidMode.OFFSET;
      composerInput = { stopEditing: () => { this.inputStops++; } };
      composerScroller = { currentOffset: () => ({ yOffset: this.scrollY }),
        scrollTo: ({ yOffset }) => { this.scrollY = yOffset; } };
      library = emptyLibrary(); libraryReady = false; libraryLoading = false; libraryBusy = false; identity = emptyIdentity();
      likedIds = []; followedIds = []; savedIds = [];
      timelinePosts = [...POSTS]; animationTriggers = [0, -1];
      timelineVisible = true; anchorCaptures = 0; selectedTab = ShellTab.Home; followingOnly = false;
      constructor(stores) {
        const paths = [];
        this.detailPaths = {
          size: () => paths.length,
          getAllPathName: () => paths.map((entry) => entry.name),
          pushPath: (entry, animated) => { paths.push(entry); this.route = entry; this.pushAnimated = animated; },
          pop: (_result, animated) => { const entry = paths.pop(); this.route = paths.at(-1); this.popAnimated = animated; entry.onPop(); }
        };
        this.stores = stores;
      }
      getUIContext() { return { getHostContext: () => this.stores,
        getKeyboardAvoidMode: () => this.keyboardMode, setKeyboardAvoidMode: (mode) => { this.keyboardMode = mode; },
        postFrameCallback: (callback) => this.frames.push(callback) }; }
      rememberReadingPosition() { this.anchorCaptures++; }
      ${timelineMethods('  onPageShow(', '  onPageHide(')}
      scheduleReadingRestore() {}
      allowsMotionFeedback() { return false; }
      inform() {}
      ${methods}
    }
    ({ Composer, DraftDecision, ShellTab });`, { mode: 'transform' }), {
    ...libraryModel, ...identityModel,
    LARGE_TEXT_SCALE: 1.4, KeyboardAvoidMode: { OFFSET: 0, RESIZE: 1, NONE: 2 },
    LayoutFrame: class { constructor(run) { this.run = run; } },
    POSTS: [{ id: 'p1', body: 'First example' }, { id: 'p2', body: 'Second example' }], SAMPLE_REPLIES: [],
    discardPostPhoto: (_context, key) => { discardedPhotos.push(key); },
    discardPostVideo: (_context, key) => { discardedVideos.push(key); },
    pickPostVideo: async (_context, fromFiles) => { videoPicks++; assert.equal(fromFiles, true); return nextVideo; },
    pickPostPhotos: async (_context, remaining) => { receivedRemaining.push(remaining); return nextPhotos; },
    postPhotoUri: (_context, key) => 'file:///test/' + key,
    preferences: { getPreferences: async (stores, { name }) => stores[name] }
  });
  const settle = () => new Promise(setImmediate);
  const discardedPhotos = [];
  const discardedVideos = [];
  let videoPicks = 0;
  let nextVideo;
  const receivedRemaining = [];
  let nextPhotos = [];
  let disk = '';
  const legacyBody = '  旧草稿第一行\n第二行 🧵  ';
  const savedBody = () => (disk ? JSON.parse(disk).body : legacyBody);
  let pending = '';
  let failWrite = false;
  let failRead = false;
  let releaseRead;
  let writes = 0;
  const store = {
    async get(key, fallback) {
      assert.ok(['body', 'content_v2'].includes(key));
      assert.equal(fallback, '');
      if (failRead) throw new Error('read failed');
      if (releaseRead) await new Promise((resolve) => { releaseRead = resolve; });
      return key === 'body' ? legacyBody : disk;
    },
    async put(key, text) { assert.equal(key, 'content_v2'); pending = text; writes++; },
    async flush() { if (failWrite) throw new Error('write failed'); disk = pending; }
  };

  let libraryDisk = '';
  let libraryPending = '';
  let libraryWrites = 0;
  let failLibraryWrite = false;
  const stores = {
    timeline_post_draft: store,
    timeline_local_library: {
      async get(key, fallback) { assert.equal(key, 'content_v1'); assert.equal(fallback, ''); return libraryDisk; },
      async put(key, text) { assert.equal(key, 'content_v1'); libraryPending = text; libraryWrites++; },
      async flush() {
        if (failLibraryWrite) throw new Error('library write failed');
        libraryDisk = libraryPending;
      }
    }
  };

  const page = new Composer(stores);
  await page.loadLibrary();
  assert.equal(page.libraryReady, true);
  page.openComposer();
  page.openComposer();
  assert.equal(page.route.name, 'PostComposer');
  assert.equal(page.anchorCaptures, 1);
  assert.equal(page.timelineVisible, false);
  assert.equal(page.pushAnimated, false);
  await settle();
  assert.equal(page.postDraftReady, true);
  assert.equal(page.postDraft, legacyBody, 'old text-only draft loads without a rewrite');
  for (const invalid of [' ', 'x'.repeat(501)]) {
    page.postDraft = invalid;
    await page.savePostDraft(false);
    page.openPostPreview();
    assert.equal(page.showingPostPreview, false);
  }
  assert.equal(writes, 0);
  const body = '  草稿第一行\n第二行 🧵  ';
  page.postDraft = body;
  const saving = page.savePostDraft(false);
  page.requestComposerExit();
  assert.ok(page.route, 'do not leave while a write is in progress');
  await page.savePostDraft(false);
  await saving;
  assert.equal(savedBody(), body, 'save exactly what was typed');
  assert.deepEqual(JSON.parse(disk), { body });
  assert.equal(writes, 1);
  assert.match(page.postDraftMessage, /已保存/);
  page.postDraft = 'unsaved change';
  page.requestComposerExit();
  assert.equal(page.draftDecision, DraftDecision.Leave);
  page.requestComposerExit();
  assert.equal(page.draftDecision, DraftDecision.None, 'Back while confirming cancels only the confirmation');
  assert.equal(page.postDraft, 'unsaved change');
  page.requestComposerExit();
  page.discardPostEdits();
  assert.equal(page.timelineVisible, true);
  assert.equal(page.popAnimated, false);
  assert.equal(savedBody(), body);

  // Compose is an action from any tab: opening, previewing and cancelling must not select Home.
  page.selectedTab = ShellTab.Activity;
  page.timelineVisible = false;
  page.openComposer();
  page.openPostPreview();
  assert.equal(page.selectedTab, ShellTab.Activity);
  page.requestComposerExit();
  page.requestComposerExit();
  assert.equal(page.route, undefined);
  assert.equal(page.selectedTab, ShellTab.Activity);
  assert.equal(page.timelineVisible, false);

  const restarted = new Composer(stores);
  restarted.openComposer();
  await settle();
  assert.equal(restarted.postDraft, body);
  restarted.postDraft = 'new draft';
  failWrite = true;
  await restarted.savePostDraft(false);
  assert.equal(savedBody(), body);
  assert.equal(restarted.postDraft, 'new draft');
  assert.match(restarted.postDraftMessage, /未能写入/);
  failWrite = false;
  await restarted.savePostDraft(true);
  assert.equal(savedBody(), body, 'clear requires confirmation');
  restarted.draftDecision = DraftDecision.Clear;
  await restarted.savePostDraft(true);
  assert.equal(restarted.postDraft, '');
  assert.deepEqual(JSON.parse(disk), { body: '' }, 'clearing must not fall back to the old draft');
  assert.match(restarted.postDraftMessage, /已清空/);
  restarted.requestComposerExit();
  assert.equal(restarted.timelineVisible, true);

  const retry = new Composer(stores);
  failRead = true;
  retry.openComposer();
  await settle();
  assert.equal(retry.postDraftReady, false);
  assert.match(retry.postDraftMessage, /重新|重试/);
  failRead = false;
  await retry.loadPostDraft();
  assert.equal(retry.postDraft, '', 'cleared draft also stays empty in a fresh page');

  const canceled = new Composer(stores);
  releaseRead = () => {};
  canceled.openComposer();
  await settle();
  canceled.requestComposerExit();
  assert.equal(canceled.timelineVisible, true);
  releaseRead();
  releaseRead = undefined;
  await settle();
  assert.equal(canceled.postDraftReady, false, 'ignore a read completed after leaving the editor');
  canceled.openComposer();
  await settle();
  assert.equal(canceled.postDraftReady, true);
  assert.match(timelineSource, /不会发布到 Threads/);

  page.openComposer();
  page.followingOnly = true;
  const preview = '  新版本\n保留换行 🧵  ';
  page.postDraft = preview;
  page.openPostPreview();
  assert.equal(page.route.name, 'PostComposer');
  assert.equal(page.previewBody, preview);
  assert.equal(page.timelinePosts.length, 2, 'preview alone must not add anything');
  page.requestComposerExit();
  assert.equal(page.showingPostPreview, false);
  assert.equal(page.postDraft, preview, 'Back goes to editing without discarding');
  const draftWritesBeforeAdd = writes;
  page.openPostPreview();
  failLibraryWrite = true;
  await page.addPreviewToTimeline();
  assert.equal(libraryDisk, '', 'failed flush does not publish the post');
  assert.equal(page.timelinePosts.length, 2);
  assert.equal(page.route.name, 'PostComposer');
  assert.equal(page.selectedTab, ShellTab.Activity, 'failed add does not leave the originating tab');
  assert.equal(page.previewBody, preview, 'failed save preserves the preview for retry');
  assert.match(page.libraryMessage, /未能保存/);

  failLibraryWrite = false;
  const libraryWritesBeforeRetry = libraryWrites;
  const add = page.addPreviewToTimeline();
  assert.equal(page.libraryBusy, true);
  await page.addPreviewToTimeline();
  await add;
  assert.equal(libraryWrites, libraryWritesBeforeRetry + 1, 'a concurrent add cannot write twice');
  assert.equal(page.timelineVisible, true);
  assert.equal(page.selectedTab, ShellTab.Home, 'only successful add returns to Home');
  assert.equal(page.followingOnly, false, 'the new local post is visible in For you');
  assert.equal(page.showingPostPreview, false);
  assert.equal(page.previewBody, '');
  const added = page.timelinePosts[0];
  assert.equal(added.body, preview);
  assert.equal(added.local, true);
  assert.match(added.id, /^local-post-[1-9][0-9]{0,14}$/);
  assert.deepEqual(Array.from(page.timelinePosts, (post) => post.id), [added.id, 'p1', 'p2']);
  assert.deepEqual(Array.from(page.animationTriggers), [-1, 0, -1], 'existing animation triggers stay with their posts');
  assert.equal(page.readingAnchor.postId, '', 'adding explicitly returns to the top');
  assert.equal(page.restorePending, true);
  assert.equal(writes, draftWritesBeforeAdd, 'adding a preview does not write to the draft store');
  page.openComposer();
  assert.equal(page.postDraft, body, 'the in-memory saved draft is unchanged by a preview');
  assert.deepEqual(JSON.parse(libraryDisk), {
    version: 1, posts: [{ id: added.id, body: preview }], likedIds: [], followedIds: [], savedIds: [], replies: [], hiddenIds: []
  });
  const reopened = new Composer(stores);
  await reopened.loadLibrary();
  assert.equal(reopened.libraryReady, true);
  assert.deepEqual(Array.from(reopened.timelinePosts, (post) => post.id), [added.id, 'p1', 'p2']);
  assert.equal(reopened.timelinePosts[0].body, preview);

  const [a, b, c, d, e] = ['1', '2', '3', '4', '5'].map((digit) => `photo-${digit.repeat(32)}.jpg`);
  disk = JSON.stringify({ body: '', photoKey: a });
  const upgrade = new Composer(stores);
  await upgrade.loadLibrary();
  upgrade.openComposer();
  await settle();
  assert.deepEqual(Array.from(upgrade.draftPhotoKeys), [a], 'the old singular draft is readable without a rewrite');
  assert.deepEqual(JSON.parse(disk), { body: '', photoKey: a });
  nextPhotos = [b, c, d];
  await upgrade.selectDraftPhotos();
  assert.deepEqual(Array.from(upgrade.draftPhotoKeys), [a, b, c, d]);
  nextPhotos = [e];
  await upgrade.selectDraftPhotos();
  assert.deepEqual(receivedRemaining, [3], 'a full draft does not reopen the picker');
  upgrade.removeDraftPhoto(d);
  assert.deepEqual(discardedPhotos.splice(0), [d], 'an unsaved, unreferenced attachment is released');
  nextPhotos = [];
  await upgrade.selectDraftPhotos();
  assert.deepEqual(receivedRemaining, [3, 1]);
  assert.deepEqual(Array.from(upgrade.draftPhotoKeys), [a, b, c], 'cancel keeps attachments and order');
  upgrade.moveDraftPhoto(c, -1);
  upgrade.moveDraftPhoto(c, -1);
  upgrade.moveDraftPhoto(c, -1);
  upgrade.moveDraftPhoto(a, 3);
  assert.deepEqual(Array.from(upgrade.draftPhotoKeys), [c, a, b], 'only adjacent, in-bounds moves apply');
  await upgrade.savePostDraft(false);
  assert.deepEqual(JSON.parse(disk), { body: '', photoKeys: [c, a, b] });
  upgrade.moveDraftPhoto(a, 1);
  assert.equal(upgrade.draftChanged(), true, 'a change to order alone marks the draft as unsaved');
  upgrade.openPostPreview();
  upgrade.removeDraftPhoto(b);
  assert.deepEqual(Array.from(upgrade.previewPhotoKeys), [c, b, a]);
  upgrade.openPhoto(upgrade.previewPhotoKeys, -1);
  assert.equal(upgrade.route.name, 'PostComposer');
  upgrade.openPhoto(upgrade.previewPhotoKeys, 1);
  assert.equal(upgrade.route.name, 'PhotoViewer');
  assert.equal(upgrade.viewerPhotoIndex, 1);
  assert.deepEqual(Array.from(upgrade.viewerPhotoKeys), [c, b, a]);
  upgrade.detailPaths.pop({ closed: true });
  assert.equal(upgrade.route.name, 'PostComposer');
  assert.equal(upgrade.viewerPhotoKeys.length, 0);
  assert.equal(upgrade.showingPostPreview, true);
  await upgrade.addPreviewToTimeline();
  assert.deepEqual(Array.from(upgrade.timelinePosts[0].photoKeys), [c, b, a]);
  assert.deepEqual(JSON.parse(disk), { body: '', photoKeys: [c, a, b] }, 'adding a post does not rewrite saved order');
  const photoReopened = new Composer(stores);
  await photoReopened.loadLibrary();
  photoReopened.openComposer();
  await settle();
  assert.deepEqual(Array.from(photoReopened.timelinePosts[0].photoKeys), [c, b, a]);
  assert.deepEqual(Array.from(photoReopened.draftPhotoKeys), [c, a, b]);
  photoReopened.draftDecision = DraftDecision.Clear;
  await photoReopened.savePostDraft(true);
  await settle();
  assert.deepEqual(JSON.parse(disk), { body: '' });
  assert.deepEqual(discardedPhotos, [], 'clearing the draft cannot delete posted images');
  photoReopened.library = libraryModel.emptyLibrary();
  await photoReopened.releasePostPhoto(b);
  assert.deepEqual(discardedPhotos, [b], 'an unreferenced image can be released');

  const video = { key: `video-${'c'.repeat(32)}.mp4`, durationMs: 7220 };
  disk = JSON.stringify({ body: '', photoKeys: [a] });
  const moving = new Composer(stores);
  await moving.loadLibrary();
  moving.openComposer();
  await settle();
  nextVideo = video;
  await moving.selectDraftVideo();
  assert.equal(videoPicks, 0, 'choosing a video cannot replace photos');
  moving.removeDraftPhoto(a);
  await moving.selectDraftVideo(true);
  assert.ok(moving.canSavePostDraft(), 'a video can be saved without a caption');
  const photoCalls = receivedRemaining.length;
  await moving.selectDraftPhotos();
  assert.equal(receivedRemaining.length, photoCalls, 'choosing photos cannot replace a video');
  await moving.savePostDraft(false);
  assert.deepEqual(JSON.parse(disk), { body: '', video });
  moving.openPostPreview();
  await moving.openVideo(moving.previewVideo);
  assert.equal(moving.route.name, 'VideoPlayer');
  await moving.openVideo(moving.previewVideo);
  assert.equal(moving.detailPaths.size(), 2, 'duplicate taps do not stack players');
  moving.detailPaths.pop({ closed: true });
  assert.equal(moving.route.name, 'PostComposer');
  assert.equal(moving.playerVideo, undefined);
  assert.equal(moving.showingPostPreview, true);
  await moving.addPreviewToTimeline();
  assert.deepEqual(JSON.parse(libraryDisk).posts[0].video, video);
  assert.deepEqual(JSON.parse(disk), { body: '', video });
  const videoReopened = new Composer(stores);
  await videoReopened.loadLibrary();
  videoReopened.openComposer();
  await settle();
  assert.equal(videoReopened.draftVideo.key, video.key);
  assert.equal(videoReopened.timelinePosts[0].video.key, video.key);
  videoReopened.draftDecision = DraftDecision.Clear;
  await videoReopened.savePostDraft(true);
  await settle();
  assert.deepEqual(discardedVideos, [], 'clearing a shared video draft keeps the posted attachment');
  videoReopened.library = libraryModel.emptyLibrary();
  await videoReopened.releasePostVideo(video.key);
  assert.deepEqual(discardedVideos, [video.key]);

  disk = JSON.stringify({ body: 'first segment' });
  const thread = new Composer(stores);
  await thread.loadLibrary();
  thread.openComposer();
  await settle();
  thread.addDraftPart();
  assert.equal(thread.activeDraftPart, 1);
  assert.equal(thread.canSavePostDraft(), true, 'an unfinished chain can be saved');
  assert.equal(thread.canPreviewPostDraft(), false, 'blank segments cannot be published');
  await thread.savePostDraft(false);
  assert.deepEqual(JSON.parse(disk), { body: 'first segment', continuation: [{ body: '' }] });
  thread.postDraft = 'second searchable';
  const secondVideo = { key: `video-${'d'.repeat(32)}.mp4`, durationMs: 5140 };
  nextVideo = secondVideo;
  await thread.selectDraftVideo(true);
  thread.addDraftPart();
  const thirdPhoto = `photo-${'a'.repeat(32)}.jpg`;
  nextPhotos = [thirdPhoto];
  await thread.selectDraftPhotos();
  thread.moveDraftPart(-1);
  assert.equal(thread.activeDraftPart, 1);
  thread.selectDraftPart(2);
  assert.equal(thread.postDraft, 'second searchable');
  assert.equal(thread.draftVideo.key, secondVideo.key);
  thread.addDraftPart();
  thread.draftDecision = DraftDecision.RemovePart;
  thread.removeDraftPart();
  assert.equal(thread.draftParts.length, 3);
  assert.equal(thread.draftVideo.key, secondVideo.key);
  const secondInput = thread.composerInputVersion;
  thread.updateComposerInput(secondInput, 'second searchable');
  thread.scrollY = 80;
  const stops = thread.inputStops;
  thread.selectDraftPart(0);
  assert.equal(thread.inputStops, stops + 1);
  assert.equal(thread.scrollY, 0, 'switching exposes the new segment rather than keeping a stale attachment offset');
  thread.updateComposerInput(secondInput, 'late change from previous input');
  assert.equal(thread.postDraft, 'first segment');
  thread.selectDraftPart(2);
  assert.equal(thread.postDraft, 'second searchable');
  await thread.savePostDraft(false);
  assert.deepEqual(JSON.parse(disk), { body: 'first segment', continuation: [{ body: '', photoKeys: [thirdPhoto] },
    { body: 'second searchable', video: secondVideo }] });
  thread.setComposerKeyboard(true);
  thread.setComposerKeyboard(true);
  assert.equal(thread.keyboardMode, 1);
  thread.viewportWidth = 320;
  assert.equal(thread.stackedComposerActions(), true);
  thread.viewportWidth = 420;
  assert.equal(thread.stackedComposerActions(), false);
  thread.fontScale = 1.75;
  assert.equal(thread.stackedComposerActions(), true);
  thread.composerHeight = 200;
  assert.equal(thread.composerActionHeight(), 92);
  thread.composerHeight = 75;
  assert.equal(thread.composerActionHeight(), 48);
  thread.scrollY = 90;
  thread.openPostPreview();
  assert.deepEqual(Array.from(thread.previewContinuation, part => part.body), ['', 'second searchable']);
  thread.updateComposerInput(thread.composerInputVersion, 'late change while previewing');
  assert.equal(thread.postDraft, 'second searchable');
  thread.requestComposerExit();
  thread.scrollY = 0;
  thread.restoreComposerOffset();
  thread.frames.shift().run();
  assert.equal(thread.scrollY, 90);
  assert.equal(thread.activeDraftPart, 2);
  thread.setComposerKeyboard(false);
  assert.equal(thread.keyboardMode, 0);
  thread.setComposerKeyboard(true);
  thread.keyboardMode = 2;
  thread.setComposerKeyboard(false);
  assert.equal(thread.keyboardMode, 2, 'do not override a newer mode after leaving');
  thread.openPostPreview();
  await thread.addPreviewToTimeline();
  const published = JSON.parse(libraryDisk).posts[0];
  assert.deepEqual(published.continuation, JSON.parse(disk).continuation);
  const threadReopened = new Composer(stores);
  await threadReopened.loadLibrary();
  threadReopened.openComposer();
  await settle();
  assert.equal(threadReopened.draftParts.length, 3);
  assert.equal(threadReopened.threadText(threadReopened.timelinePosts[0]), 'first segment\n\nsecond searchable');
  threadReopened.searchQuery = 'searchable';
  threadReopened.hiddenIds = [];
  assert.ok(threadReopened.discoveryPosts().some(post => post.id === published.id));
  threadReopened.libraryMode = 0;
  for (const mediaMode of [1, 2]) {
    threadReopened.profileMediaMode = mediaMode;
    assert.ok(threadReopened.profilePosts().some(post => post.id === published.id), 'any segment matches media filter');
  }
  threadReopened.draftDecision = DraftDecision.Clear;
  await threadReopened.savePostDraft(true);
  assert.ok(!discardedPhotos.includes(thirdPhoto) && !discardedVideos.includes(secondVideo.key),
    'clearing a thread draft cannot remove published continuation attachments');
  assert.match(timelineSource, /ForEach\(this\.visibleFeed\(\),/);
});

test('Stage bundle names agree and signing remains disabled', () => {
  const bundle = appConfig.app.bundleName;
  assert.equal(bundle, 'com.tvtjiesen.threadsharmony');
  assert.equal(buildConfig.app.products[0].bundleName, bundle);
  assert.deepEqual(buildConfig.app.signingConfigs, []);
});

test('Stage declares phone support without removing tablet and 2in1', () => {
  const { module } = JSON.parse(readFileSync(new URL('../app/entry/src/main/module.json5', import.meta.url), 'utf8'));
  assert.deepEqual(module.deviceTypes, ['phone', 'tablet', '2in1']);
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

test('system browser fallback opens only the fixed Threads URL and shows a manual fallback on failure', async () => {
  const home = app.match(/^const HOME_URL: string = .+;$/m)?.[0];
  assert.ok(home, 'the ArkWeb page must declare a fixed home URL');
  const method = app.slice(app.indexOf('  private async openExternalHome('), app.indexOf('  private goBack('))
    .replace('private async', 'async');
  const Harness = vm.runInNewContext(stripTypeScriptTypes(`${home}\nclass Harness {
    externalHomeFailed = true;
    proxyActive = 'proxy.example:8080';
    proxyPending = true;
    getUIContext() { return { getHostContext: () => this.context }; }
    ${method}
  }; Harness`));
  const page = new Harness();
  const opened = [];
  page.context = { openLink: async (url, options) => { opened.push([url, { ...options }]); } };
  await page.openExternalHome();
  assert.deepEqual(opened, [['https://www.threads.com/', { appLinkingOnly: false }]], 'no proxy or user-supplied URL is forwarded');
  assert.equal(page.externalHomeFailed, false);
  page.context = { openLink: async () => { throw new Error('no browser handler'); } };
  await page.openExternalHome();
  assert.equal(page.externalHomeFailed, true);
  page.externalHomeFailed = false;
  page.context = undefined;
  await page.openExternalHome();
  assert.equal(page.externalHomeFailed, true);
  assert.match(app, /Button\('通过系统打开 Threads 网页'\)\.onClick\(\(\) => \{ this\.openExternalHome\(\); \}\)/);
  assert.match(app, /if \(this\.externalHomeFailed\) \{\s+Text\(`[^`]*\$\{HOME_URL\}`\)/);
});

test('candidate keeps navigation, TLS, permission, and HTTP error guardrails', () => {
  assert.match(overlay, /TOP_LEVEL_HOSTS\.includes\(parsed\.hostname\.toLowerCase\(\)\)/);
  assert.match(overlay, /event\.request\.deny\(\)/);
  assert.match(overlay, /event\.handler\.handleCancel\(\)/);
  assert.match(overlay, /onHttpErrorReceive\(\(event\) =>/);
});
