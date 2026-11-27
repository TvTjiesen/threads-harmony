import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';
import { test } from 'node:test';

const read = name => readFileSync(new URL(`../app/entry/src/main/ets/${name}`, import.meta.url), 'utf8');
const video = read('components/PostVideo.ets');

function makePlayer() {
  const helpers = video.slice(0, video.indexOf('@Component'));
  const methods = video.slice(video.indexOf('  aboutToAppear()'), video.indexOf('  @Builder\n  PlayerControls'))
    .replace(/^  private /gm, '  ');
  const sliderMode = { Begin: 0, Moving: 1, End: 2 };
  const calls = [];
  class Controller {
    start() { calls.push('start'); }
    pause() { calls.push('pause'); }
    stop() { calls.push('stop'); }
    setCurrentTime(value, mode) { calls.push(['seek', value, mode]); }
  }
  const Player = runInNewContext(stripTypeScriptTypes(`${helpers}\nclass Player { ${methods} }\nPlayer`), {
    SliderChangeMode: sliderMode, SeekMode: { Accurate: 1 }, VideoController: Controller
  });
  const player = Object.assign(new Player(), { controller: new Controller(), durationMs: 8000, mediaDuration: 0,
    playbackPosition: 0, active: true, finished: false, prepared: false, failed: false });
  player.aboutToAppear();
  return { player, calls, sliderMode };
}

test('native video never autoplays and loses playback intent when hidden or backgrounded', () => {
  const { player, calls } = makePlayer();
  player.togglePlayback();
  assert.deepEqual(calls, [], 'controls stay disabled until the native video is prepared');
  player.prepared = true;
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
  player.prepared = true;
  player.sliderChanged(75, sliderMode.Begin);
  player.updatePosition(2);
  assert.equal(player.visiblePosition(), 6);
  assert.deepEqual(calls, []);
  player.sliderChanged(75, sliderMode.End);
  player.seekTo(99);
  assert.equal(player.finished, true);
  player.togglePlayback();
  assert.equal(player.playbackPosition, 0);
  assert.deepEqual(calls, [['seek', 6, 1], ['seek', 8, 1], ['seek', 0, 1], 'start']);
  player.failPlayback();
  player.togglePlayback();
  assert.equal(player.wantsPlayback, false);
  assert.equal(calls.at(-1), 'pause');
  player.retryPlayback();
  assert.equal(player.failed, false);
  assert.equal(player.canControl(), false, 'retry waits for preparation instead of starting');
});
