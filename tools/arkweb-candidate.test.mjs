import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import { test } from 'node:test';

const overlay = readFileSync(new URL('../overlay/entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const app = readFileSync(new URL('../app/entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const timelineSource = readFileSync(new URL('../app/entry/src/main/ets/pages/Timeline.ets', import.meta.url), 'utf8');
const librarySource = readFileSync(new URL('../app/entry/src/main/ets/model/LocalLibrary.ets', import.meta.url), 'utf8');
const libraryModel = await import(`data:text/javascript,${encodeURIComponent(stripTypeScriptTypes(librarySource))}`);

function timelineMethods(start, end) {
  const first = timelineSource.indexOf(start);
  const last = timelineSource.indexOf(end, first + start.length);
  assert.ok(first >= 0 && last > first, `cannot extract Timeline methods between ${start} and ${end}`);
  return timelineSource.slice(first, last).replace(/^  private (?:readonly )?/gm, '  ');
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
  assert.match(timeline, /不會连接|不会连接/);
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
  }; Timeline`), { emptyLibrary: libraryModel.emptyLibrary });
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
  assert.match(timelineSource, /Toggle\(\{ type: ToggleType\.Switch, isOn: this\.reduceMotion \}\)/);
  assert.match(timelineSource, /\.onChange\(\(enabled: boolean\) => \{ this\.updateMotionPreference\(enabled\); \}\)/);
  assert.match(timelineSource, /\.bindSheet\(\$\$this\.settingsVisible, this\.SettingsSheet\(\), \{/);
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
    async saveLibrary(value) { this.library = value; this.likedIds = value.likedIds; return true; }
    ${nextSelection}
    ${methods}
  }; Timeline`), { POSTS: [{ id: 'p1' }], DISPLAY_PREFERENCES: 'timeline_display', REDUCE_MOTION_KEY: 'reduce_motion',
    preferences, accessibility, emptyLibrary: libraryModel.emptyLibrary });

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

test('settings sheet has one explicit close control and synchronized dismiss state', () => {
  const timeline = readFileSync(new URL('../app/entry/src/main/ets/pages/Timeline.ets', import.meta.url), 'utf8');
  const settings = timeline.slice(timeline.indexOf('  SettingsSheet()'), timeline.indexOf('  PostCard('));
  assert.match(settings, /Button\('完成',/);
  assert.match(settings, /this\.settingsVisible = false/);
  assert.match(timeline, /\.bindSheet\(\$\$this\.settingsVisible, this\.SettingsSheet\(\), \{/);
  assert.match(timeline, /showClose: false/);
  assert.doesNotMatch(timeline, /showClose: true/);
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

test('Stage follows system font scale and timeline reflows when text grows', () => {
  const timeline = readFileSync(new URL('../app/entry/src/main/ets/pages/Timeline.ets', import.meta.url), 'utf8');
  assert.equal(appConfig.app.configuration, '$profile:configuration');
  assert.deepEqual(fontConfig.configuration, { fontSizeScale: 'followSystem', fontSizeMaxScale: '3.2' });
  const ability = readFileSync(new URL('../app/entry/src/main/ets/entryability/EntryAbility.ets', import.meta.url), 'utf8');
  assert.match(ability, /onConfigurationUpdate\(config: Configuration\)[\s\S]*AppStorage\.setOrCreate\('timelineFontScale', config\.fontSizeScale/);
  assert.match(ability, /this\.onConfigurationUpdate\(this\.context\.config\);\s+windowStage\.loadContent\('pages\/Timeline'\)/);
  assert.match(timeline, /@StorageProp\('timelineFontScale'\)/);
  assert.match(timeline, /\.lanes\(this\.readingLaneCount\(\), 12\)/);
  assert.match(timeline, /this\.viewportWidth >= WIDE_VIEWPORT && !this\.toolbarInList\(\) \? 2 : 1/);
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
    detailPaths = { size: () => 0 };
    getUIContext() { return { postFrameCallback: (frame) => frames.push(frame) }; }
    ${methods}
  }; Timeline`), {
    POSTS: [{ id: 'p1' }, { id: 'p2' }, { id: 'p3' }], LARGE_TEXT_SCALE: 1.4, WIDE_VIEWPORT: 680,
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
});

test('post detail uses one stack entry and keeps replies local and scoped to their post', () => {
  const methods = timelineMethods('  private openPost(', '  private localPost(');
  const post = { id: 'p1', replies: 12 };
  const other = { id: 'p2', replies: 7 };
  const Timeline = vm.runInNewContext(stripTypeScriptTypes(`class Timeline {
    timelineVisible = true; replyDraft = 'old draft'; replySequence = 0; localReplies = [];
    motion = false; anchorCaptures = 0; timelinePosts = POSTS;
    allowsMotionFeedback() { return this.motion; }
    rememberReadingPosition() { this.anchorCaptures++; }
    onPageShow() { this.timelineVisible = this.detailPaths.size() === 0; }
    ${methods}
  }; Timeline`), {
    POSTS: [post, other], POST_DETAIL: 'PostDetail', POST_SEARCH: 'LocalSearch', POST_LIBRARY: 'LocalLibrary',
    REPLY_LIMIT: 280,
    SAMPLE_REPLIES: [{ id: 's1', postId: 'p1', body: 'sample' }]
  });
  const page = new Timeline();
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
  for (const draft of [' \n ', 'a'.repeat(281)]) {
    page.replyDraft = draft;
    page.submitReply('p1');
  }
  page.replyDraft = '  第一条本地回复  ';
  page.submitReply('missing');
  assert.equal(page.localReplies.length, 0);
  page.submitReply('p1');
  assert.equal(page.replyDraft, '');
  assert.equal(page.replyCount(post), 13);
  assert.equal(page.replyCount(other), 7);
  assert.deepEqual(Array.from(page.repliesFor('p1'), (reply) => reply.body), ['第一条本地回复', 'sample']);
  assert.equal(page.repliesFor('p2').length, 0);
  page.replyDraft = '未提交的草稿';
  page.closePost();
  page.closePost();
  assert.equal(page.replyDraft, '');
  assert.equal(page.timelineVisible, true);
  page.motion = true;
  page.openPost(other);
  page.closePost();
  assert.deepEqual(transitions, [false, false, true, true]);
  assert.equal(page.replyCount(post), 13);
  assert.equal(new Timeline().replyCount(post), 12, 'local replies do not survive a fresh page');
  for (const source of ['LocalSearch', 'LocalLibrary']) {
    stack.push({ name: source });
    page.openPost(post);
    page.openPost(other);
    assert.deepEqual(stack.map(({ name }) => name), [source, 'PostDetail']);
    assert.equal(stack[1].param.id, post.id);
    page.closePost();
    assert.equal(page.timelineVisible, false);
    assert.deepEqual(stack.map(({ name }) => name), [source]);
    stack.pop();
  }
  assert.match(timelineSource, /Navigation\(this\.detailPaths\)/);
  assert.match(timelineSource, /\.onBackPressed\(\(\) => \{\s*this\.closePost\(\)/);
  assert.match(timelineSource, /this\.PostCard\(post, true\)/);
  assert.match(timelineSource, /this\.PostCard\(post, false\)/);
});

test('post drafts persist explicitly and preview posts are added once without modifying the saved draft', async () => {
  const constants = timelineSource.slice(timelineSource.indexOf('const POST_COMPOSER'), timelineSource.indexOf('interface DemoReply'));
  const methods = timelineMethods('  private localPost(', '  @Builder\n  SettingsSheet()');
  const { Composer, DraftDecision } = vm.runInNewContext(stripTypeScriptTypes(`
    ${constants}
    class Composer {
      postDraft = ''; savedPostDraft = ''; postDraftReady = false; postDraftBusy = false;
      postDraftMessage = ''; draftDecision = DraftDecision.None; postDraftLoadId = 0;
      showingPostPreview = false; previewBody = ''; postSequence = 0;
      library = emptyLibrary(); libraryReady = false; libraryLoading = false; libraryBusy = false;
      likedIds = []; followedIds = []; savedIds = [];
      timelinePosts = [...POSTS]; animationTriggers = [0, -1];
      timelineVisible = true; anchorCaptures = 0;
      constructor(stores) {
        this.detailPaths = {
          size: () => this.route ? 1 : 0,
          pushPath: (entry, animated) => { this.route = entry; this.pushAnimated = animated; },
          pop: (_result, animated) => { const entry = this.route; this.route = undefined; this.popAnimated = animated; entry.onPop(); }
        };
        this.stores = stores;
      }
      getUIContext() { return { getHostContext: () => this.stores }; }
      rememberReadingPosition() { this.anchorCaptures++; }
      onPageShow() { this.timelineVisible = true; }
      allowsMotionFeedback() { return false; }
      inform() {}
      ${methods}
    }
    ({ Composer, DraftDecision });`, { mode: 'transform' }), {
    ...libraryModel,
    POSTS: [{ id: 'p1' }, { id: 'p2' }],
    preferences: { getPreferences: async (stores, { name }) => stores[name] }
  });
  const settle = () => new Promise(setImmediate);
  let disk = '';
  let pending = '';
  let failWrite = false;
  let failRead = false;
  let releaseRead;
  let writes = 0;
  const store = {
    async get(key, fallback) {
      assert.equal(key, 'body');
      assert.equal(fallback, '');
      if (failRead) throw new Error('read failed');
      if (releaseRead) await new Promise((resolve) => { releaseRead = resolve; });
      return disk;
    },
    async put(key, text) { assert.equal(key, 'body'); pending = text; writes++; },
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
  assert.equal(disk, body, 'save exactly what was typed');
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
  assert.equal(disk, body);

  const restarted = new Composer(stores);
  restarted.openComposer();
  await settle();
  assert.equal(restarted.postDraft, body);
  restarted.postDraft = 'new draft';
  failWrite = true;
  await restarted.savePostDraft(false);
  assert.equal(disk, body);
  assert.equal(restarted.postDraft, 'new draft');
  assert.match(restarted.postDraftMessage, /未能写入/);
  failWrite = false;
  await restarted.savePostDraft(true);
  assert.equal(disk, body, 'clear requires confirmation');
  restarted.draftDecision = DraftDecision.Clear;
  await restarted.savePostDraft(true);
  assert.equal(restarted.postDraft, '');
  assert.equal(disk, '');
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
    version: 1, posts: [{ id: added.id, body: preview }], likedIds: [], followedIds: [], savedIds: []
  });
  const reopened = new Composer(stores);
  await reopened.loadLibrary();
  assert.equal(reopened.libraryReady, true);
  assert.deepEqual(Array.from(reopened.timelinePosts, (post) => post.id), [added.id, 'p1', 'p2']);
  assert.equal(reopened.timelinePosts[0].body, preview);
  assert.match(timelineSource, /ForEach\(this\.timelinePosts,/);
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
