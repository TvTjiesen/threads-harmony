import assert from 'node:assert/strict';
import { stat, writeFile } from 'node:fs/promises';
import { test } from 'node:test';
import { BUNDLE, parseTree } from './device-smoke.mjs';
import { main, uiSmoke } from './web-device-smoke.mjs';

const EXE = process.platform === 'win32' ? 'C:/DevEco Studio/toolchains/hdc.exe' : '/opt/DevEco Studio/toolchains/hdc';
const SERIAL = 'TEST-TARGET-1234';
const ARGS = ['--hdc', EXE, '--serial', SERIAL];
const PRIVATE = 'do-not-print-raw-content';
const node = (id, x, y, attr = {}) => ({ attributes: { id, bounds: `[${x},${y}][${x + 40},${y + 40}]`, ...attr } });
const tree = (...children) => JSON.stringify({ children });
const nav = node('nav-profile', 340, 600, { selected: 'true' });
const entry = node('library-web', 60, 180);
const back = node('web-back', 0, 20);
const reload = node('web-reload', 360, 20);
const settings = node('web-settings', 300, 20);
const localHome = node('web-local-home', 240, 20);
const done = node('web-settings-done', 50, 440);
const profile = tree(nav, entry);
const toolbar = tree(back, reload, settings, localHome);
const sheet = tree(done);
const click = (x, y) => ['shell', 'uitest', 'uiInput', 'click', String(x), String(y)];
const clicks = [click(80, 200), click(320, 40), click(70, 460), click(260, 40)];

function capture() {
  const messages = [];
  const append = message => messages.push(message);
  return { messages, log: append, error: append };
}

test('no device access without valid explicit --ui, HDC executable and exact target', async () => {
  const cases = [
    [[], 0, /Usage:/], [['--help'], 0, /ArkWeb/], [ARGS, 2, /--ui is required/],
    [['--ui'], 2, /both required/], [[...ARGS, '--ui', '--ui'], 2, /not be repeated/],
    [['--ui', '--hdc', 'hdc', '--serial', SERIAL], 2, /absolute local/],
    [['--ui', '--hdc', EXE, '--serial', `${SERIAL};${PRIVATE}`], 2, /exact HDC/],
    [[...ARGS, '--ui', '--command', PRIVATE], 2, /Unknown argument/],
  ];
  for (const [args, status, message] of cases) {
    let calls = 0;
    const out = capture();
    const result = await main(args, { ...out, execute() { calls++; } });
    assert.equal(result, status);
    assert.equal(calls, 0);
    assert.match(out.messages[0], message);
    assert.doesNotMatch(out.messages[0], new RegExp(`${SERIAL}|${PRIVATE}`));
  }
});

test('opt-in CLI uses a fresh bundle-scoped tree per tap and only four allowlisted native taps', async () => {
  const fallbackToolbar = tree(back, reload, settings, localHome,
    node('web-notice', 0, 100, { text: PRIVATE }), node('web-failure-retry', 20, 140),
    node('web-failure-browser', 140, 140));
  const modal = tree(done, node('web-proxy-input', 10, 220, { text: PRIVATE }),
    node('web-proxy-save', 10, 270), node('web-proxy-clear', 10, 320), node('web-settings-browser', 10, 370));
  const stages = [profile, toolbar, modal, fallbackToolbar, profile];
  const seen = new Set();
  const locals = [];
  const out = capture();
  let stage = 0;
  let remote;
  let phase = 'dump';
  let mockFailure;
  function execute(file, argv, opts, complete) {
    async function mock() {
      assert.equal(file, EXE);
      assert.equal(opts.shell, false);
      assert.deepEqual(argv.slice(0, 2), ['-t', SERIAL]);
      const cmd = argv.slice(2);
      switch (phase) {
        case 'dump':
          remote = cmd.at(-1);
          assert.ok(!seen.has(remote));
          seen.add(remote);
          assert.match(remote, /^\/data\/local\/tmp\/threads-smoke-[a-f0-9-]{36}\.json$/);
          assert.deepEqual(cmd, ['shell', 'uitest', 'dumpLayout', '-b', BUNDLE, '-a', '-p', remote]);
          phase = 'recv';
          return `DumpLayout saved to ${remote}`;
        case 'recv': {
          const local = cmd.at(-1);
          assert.deepEqual(cmd, ['file', 'recv', remote, local]);
          locals.push(local);
          await writeFile(local, stages[stage], 'utf8');
          phase = 'cleanup';
          return 'FileTransfer finish';
        }
        case 'cleanup':
          assert.deepEqual(cmd, ['shell', 'rm', '-f', remote]);
          phase = stage < clicks.length ? 'click' : 'complete';
          return '';
        case 'click':
          assert.deepEqual(cmd, clicks[stage]);
          stage++;
          phase = 'dump';
          return '';
        default:
          assert.fail(`Unexpected HDC invocation after final snapshot: ${phase}`);
      }
    }
    mock().then(stdout => complete(null, stdout, PRIVATE), err => {
      mockFailure = err;
      complete(err, '', PRIVATE);
    });
  }
  const status = await main([...ARGS, '--ui'], { ...out, execute });
  if (mockFailure) throw mockFailure;
  assert.equal(status, 0);
  assert.equal(stage, clicks.length);
  assert.equal(phase, 'complete');
  assert.equal(seen.size, stages.length);
  await Promise.all(locals.map(async local => assert.rejects(stat(local), { code: 'ENOENT' })));
  assert.deepEqual(out.messages, [
    'PASS ArkWeb native toolbar actions visible from root Profile',
    'PASS native network sheet opened and closed',
    'PASS Local Home returned to root Profile (native chrome only)',
  ]);
});

test('stops at the first missing, hidden, disabled, duplicate or unconfirmed native state', async () => {
  const cases = [
    [[tree(node('nav-profile', 340, 600, { selected: 'false' }), entry)], /Open Web from root Profile/],
    [[tree(nav, node('library-web', 60, 180, { visible: 'false' }))], /Open Web from root Profile/],
    [[tree(nav, node('library-web', -80, 180))], /Open Web from root Profile/],
    [[profile, tree(back, settings, localHome)], /ArkWeb native toolbar/],
    [[profile, tree(back, reload, settings, localHome, node('web-settings', 90, 90))], /ArkWeb native toolbar/],
    [[profile, toolbar, tree(node('web-settings-done', 50, 440, { enabled: 'false' }))], /Network sheet \/ Done/],
    [[profile, toolbar, sheet, tree(back, reload, settings, localHome, done)], /Network sheet closed/],
    [[profile, toolbar, sheet, toolbar, toolbar], /Local Home returns to root Profile/],
  ];
  for (const [stages, expected] of cases) {
    const seen = [];
    let captures = 0;
    await assert.rejects(uiSmoke(async (_label, ...command) => {
      seen.push(command);
      return '';
    }, () => {}, {
      snapshot: async () => { captures++; return parseTree(stages[seen.length]); },
      pause: async () => {},
    }), expected);
    assert.deepEqual(seen, clicks.slice(0, stages.length - 1));
    assert.equal(captures, seen.length + 5);
  }
});

test('waits for transitions and reports failures without raw HDC or tree data', async () => {
  const seen = [];
  const stages = [profile, profile, toolbar, sheet];
  await assert.rejects(uiSmoke(async (_label, ...command) => {
    seen.push(command);
    return seen.length === 3 ? `[Fail] ${PRIVATE}` : '';
  }, () => {}, {
    snapshot: async () => parseTree(stages.shift()), pause: async () => {},
  }), { message: 'Network sheet / Done: UITest click failed.' });
  assert.deepEqual(seen, clicks.slice(0, 3));
  await assert.rejects(uiSmoke(() => assert.fail('must not click on snapshot error'), () => {}, {
    snapshot: async () => { throw new Error(PRIVATE); }, pause: async () => {},
  }), { message: 'Open Web from root Profile: app-scoped UI snapshot or temporary tree cleanup failed.' });
});
