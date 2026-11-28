import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';
import { test } from 'node:test';

const read = name => readFileSync(new URL(`../app/entry/src/main/ets/${name}`, import.meta.url), 'utf8');
const video = read('components/PostVideo.ets');
const photo = read('components/PostPhoto.ets');

function extractComponent(source, name, globals = {}) {
  const helpers = source.slice(0, source.indexOf('@Component'));
  const declaration = source.indexOf(`export struct ${name} {`);
  const implementation = source.slice(declaration).split(/\n  (?:@Builder|build\(\))/u, 1)[0]
    .replace(`export struct ${name}`, `class ${name}`)
    .replace(/@Prop\s+|@Watch\('[^']+'\)\s+|@State\s+|\bprivate /g, '');
  return runInNewContext(stripTypeScriptTypes(`${helpers}\n${implementation}}\n${name}`), globals);
}

function makePlayer() {
  const sliderMode = { Begin: 0, Moving: 1, End: 2, Click: 3 };
  const calls = [];
  class Controller {
    start() { calls.push('start'); }
    pause() { calls.push('pause'); }
    stop() { calls.push('stop'); }
    setCurrentTime(value, mode) { calls.push(['seek', value, mode]); }
  }
  const Player = extractComponent(video, 'PostVideoPlayer', {
    SliderChangeMode: sliderMode, SeekMode: { Accurate: 1 }, VideoController: Controller
  });
  const player = Object.assign(new Player(), { uri: 'file://thread/video.mp4', durationMs: 8000, active: true });
  player.aboutToAppear();
  return { player, calls, sliderMode };
}

test('native video never autoplays and loses playback intent when hidden or backgrounded', () => {
  const { player, calls } = makePlayer();
  player.togglePlayback();
  assert.deepEqual(calls, [], 'controls stay disabled until the native video is prepared');
  player.preparedPlayback(0, 8);
  player.togglePlayback();
  assert.equal(player.wantsPlayback, true);
  player.active = false;
  player.onActiveChange();
  player.togglePlayback();
  assert.equal(player.wantsPlayback, false);
  player.active = true;
  player.onActiveChange();
  assert.deepEqual(calls, ['start', 'pause'], 'returning to foreground does not resume');
  player.aboutToDisappear();
  player.aboutToDisappear();
  assert.deepEqual(calls, ['start', 'pause', 'stop']);
  assert.match(video, /\.autoPlay\(false\)\.controls\(false\)\.loop\(false\)/);
  assert.match(read('pages/Timeline.ets'), /active: this\.appForeground && this\.videoDestinationVisible/);
  assert.match(read('entryability/EntryAbility.ets'), /onBackground\(\)[\s\S]*?AppStorage\.setOrCreate\('timelineAppForeground', false\)/);
});

test('slider scrubbing, replay and playback error preserve control boundaries', () => {
  const { player, calls, sliderMode } = makePlayer();
  player.preparedPlayback(0, 8);
  player.sliderChanged(75, sliderMode.Begin);
  player.updatePosition(0, 2, true);
  assert.equal(player.visiblePosition(), 6);
  assert.deepEqual(calls, []);
  player.sliderChanged(75, sliderMode.End);
  player.seekTo(99);
  assert.equal(player.finished, true);
  player.togglePlayback();
  assert.equal(player.playbackPosition, 0);
  assert.deepEqual(calls, [['seek', 6, 1], ['seek', 8, 1], ['seek', 0, 1], 'start']);
  player.failPlayback(0);
  player.togglePlayback();
  assert.equal(player.wantsPlayback, false);
  assert.equal(calls.at(-1), 'stop');
  player.retryPlayback();
  assert.equal(player.failed, false);
  assert.equal(player.canControl(), false, 'retry waits for preparation instead of starting');
});

test('retry and source replacement isolate late native events from the new controller', () => {
  const { player, calls } = makePlayer();
  const initialController = player.controller;
  player.preparedPlayback(0, 8);
  player.togglePlayback();
  player.failPlayback(0);
  player.active = false;
  player.onActiveChange();
  player.retryPlayback();
  assert.equal(player.controller, initialController, 'hidden players cannot retry');
  player.active = true;
  player.retryPlayback();
  assert.notEqual(player.controller, initialController);
  assert.equal(player.session, 1);
  player.preparedPlayback(0, 80);
  player.failPlayback(0);
  player.startedPlayback(0);
  assert.equal(player.canControl(), false);
  assert.deepEqual(calls, ['start', 'stop'], 'superseded callbacks never touch the replacement controller');
  player.preparedPlayback(1, 8);
  player.togglePlayback();
  player.pausedPlayback(0);
  player.finishedPlayback(0);
  player.updatePosition(0, 4, false);
  assert.equal(player.wantsPlayback, true);
  assert.equal(player.finished, false);
  assert.equal(player.visiblePosition(), 0);
  player.uri = 'file://thread/next.mp4';
  player.onSourceChange();
  assert.equal(player.session, 2);
  assert.equal(player.wantsPlayback, false);
  assert.equal(player.canControl(), false);
  assert.deepEqual(calls, ['start', 'stop', 'start', 'stop']);
  assert.match(video, /ForEach\(\[this\.session\][\s\S]*?this\.VideoSurface\(session\)[\s\S]*?String\(session\)/);
  assert.match(video, /\.onError\(\(\) => \{ this\.failPlayback\(session\); \}\)/);
});

test('native progress samples within one display bucket do not write reactive position', () => {
  const { player, calls, sliderMode } = makePlayer();
  let shown = 0;
  let writes = 0;
  Object.defineProperty(player, 'playbackPosition', {
    get: () => shown, set: value => { shown = value; writes++; }
  });
  player.preparedPlayback(0, 8);
  player.togglePlayback();
  for (let frame = 1; frame <= 60; frame++) { player.updatePosition(0, frame / 60, false); }
  assert.equal(writes, 4, '60 increasing native samples in one playback second cause four display writes');
  assert.equal(shown, 1);
  player.updatePosition(0, 1.129, false);
  assert.equal(shown, 1);
  assert.equal(player.exactPosition, 1.129);
  player.sliderChanged(NaN, sliderMode.Moving);
  assert.equal(player.visiblePosition(), 1);
  player.sliderChanged(37, sliderMode.Click);
  player.sliderChanged(37, sliderMode.End);
  assert.deepEqual(calls, ['start', ['seek', 2.96, 1]], 'click followed by end seeks only once');
  player.updatePosition(0, 2.971, true);
  player.updatePosition(0, 2.99, false);
  player.updatePosition(0, 2.9, false);
  assert.equal(shown, 2.971, 'rounding and late samples cannot pull the slider back after a seek');
  player.togglePlayback();
  player.updatePosition(0, 3.25, false);
  assert.equal(shown, 2.971, 'late playback samples do not advance a paused UI');
  player.finishedPlayback(0);
  assert.equal(shown, 8, 'completion always surfaces the exact endpoint');
});

test('four-photo viewer retains only current and adjacent readiness without losing the selected photo', () => {
  const PhotoViewer = extractComponent(photo, 'PhotoViewer', { SwiperController: class {} });
  const uris = ['file://one', 'file://two', 'file://three', 'file://four'];
  const viewer = Object.assign(new PhotoViewer(), { uris, initialIndex: 2 });
  viewer.aboutToAppear();
  assert.equal(viewer.index, 2);
  uris.forEach((uri, index) => viewer.setPhotoReady(uri, index, true));
  assert.deepEqual(Array.from(viewer.ready, Boolean), [false, true, true, true]);
  viewer.zoomed = true;
  viewer.pageChanged(1);
  assert.equal(viewer.zoomed, false);
  assert.equal(viewer.ready[3], false);
  viewer.setPhotoReady(uris[3], 3, true);
  assert.equal(viewer.ready[3], false, 'ignore callbacks from an out-of-window page');
  viewer.uris = [uris[0], uris[1], 'file://changed', uris[3]];
  viewer.resetGallery();
  assert.equal(viewer.ready[2], false, 'replaced image is not regarded as decoded');
  viewer.setPhotoReady(uris[2], 2, true);
  assert.equal(viewer.ready[2], false);
  assert.match(photo, /if \(inPhotoWindow\(index, this\.index\)\) \{\s+PostPhoto\(/);
  assert.match(photo, /if \(inPhotoWindow\(index, this\.index\)\) \{\s+ViewerPhotoPage\(/);
});
