import assert from 'node:assert/strict';
import { stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { test } from 'node:test';
import { BUNDLE, createHdc, dumpTree, main, parseArgs, parseTree, uiSmoke } from './device-smoke.mjs';

const exe = process.platform === 'win32' ? 'C:/DevEco Studio/toolchains/hdc.exe' : '/opt/DevEco Studio/toolchains/hdc';
const serial = 'DEMO-TEST-5555';
const args = ['--hdc', exe, '--serial', serial];
const privateText = 'do-not-log-this-test-content';

const node = (id, rest = {}, children = []) => ({ attributes: { id, bounds: '[0,0][80,120]', ...rest }, children });
const tree = (...nodes) => JSON.stringify({ children: nodes });

function capture() {
  const messages = [];
  const append = message => messages.push(message);
  return { messages, log: append, error: append };
}

test('requires an explicit exact target and a local absolute HDC path; UI defaults off', () => {
  assert.deepEqual(parseArgs(args), { hdc: exe, serial, ui: false });
  assert.deepEqual(parseArgs(['--ui', ...args]), { hdc: exe, serial, ui: true });
  assert.deepEqual(parseArgs(['--help']), { help: true });
  for (const invalid of [[], ['--ui'], ['--hdc', exe], ['--serial', serial],
    ['--hdc', 'hdc', '--serial', serial], [...args, '--ui', '--ui'], [...args, '--hdc', exe],
    [...args, '--serial', serial], [...args, '--help'], ['--hdc', exe, '--serial', '--ui'],
    ['--hdc', exe, '--serial', 'abc; bad'], [...args, privateText]]) {
    assert.throws(() => parseArgs(invalid), error => !error.message.includes(privateText));
  }
  const onWindows = hdc => parseArgs(['--hdc', hdc, '--serial', '127.0.0.1:5555'], 'win32');
  assert.equal(onWindows('C:/DevEco Studio/hdc.exe').hdc, 'C:/DevEco Studio/hdc.exe');
  assert.equal(onWindows(String.raw`D:\DevEco Studio\hdc.exe`).hdc, String.raw`D:\DevEco Studio\hdc.exe`);
  for (const invalid of ['/hdc.exe', String.raw`\hdc.exe`, 'D:hdc.exe', String.raw`\\host\share\hdc.exe`]) {
    assert.throws(() => onWindows(invalid), /absolute local/);
  }
});

test('uses execFile callback without a shell; errors do not return private HDC output', async () => {
  const hdc = createHdc({ hdc: exe, serial }, (file, argv, opts, done) => {
    assert.equal(file, exe);
    assert.deepEqual(argv, ['-t', serial, 'shell', 'param', 'get', 'const.ohos.apiversion']);
    assert.equal(opts.shell, false);
    assert.equal(opts.windowsHide, true);
    assert.equal(opts.encoding, 'utf8');
    assert.ok(opts.timeout > 0 && opts.timeout <= 30_000);
    assert.ok(opts.maxBuffer > 0);
    queueMicrotask(() => done(null, ' 26\r\n', privateText));
  });
  assert.equal(await hdc('API query', 'shell', 'param', 'get', 'const.ohos.apiversion'), '26');
  const timedOut = createHdc({ hdc: exe, serial }, (_file, _argv, _opts, done) => {
    done(Object.assign(new Error(privateText), { killed: true }), privateText, privateText);
  });
  await assert.rejects(timedOut('API query'), { message: 'API query: HDC timed out or was stopped. Check the executable and selected connection.' });
  const failedOnStderr = createHdc({ hdc: exe, serial }, (_file, _argv, _opts, done) => {
    done(null, '26', `[Fail] ${privateText}`);
  });
  await assert.rejects(failedOnStderr('API query'), { message: 'API query: HDC failed. Check the executable and selected connection.' });
});

test('help and usage failure never call HDC; diagnostics issue only selected read-only queries', async () => {
  for (const [argv, expected] of [[['--help'], 0], [['--ui'], 2], [[privateText], 2]]) {
    const out = capture();
    let calls = 0;
    assert.equal(await main(argv, { ...out, execute() { calls++; } }), expected);
    assert.equal(calls, 0);
    assert.doesNotMatch(out.messages.join('\n'), new RegExp(privateText));
  }
  const calls = [];
  const out = capture();
  assert.equal(await main(args, { ...out, execute(file, argv, _opts, done) {
    assert.equal(file, exe);
    calls.push(argv);
    done(null, calls.length === 1 ? '26\n' : `${BUNDLE}:\n${JSON.stringify({ name: BUNDLE, details: privateText })}`, privateText);
  } }), 0);
  assert.deepEqual(calls, [
    ['-t', serial, 'shell', 'param', 'get', 'const.ohos.apiversion'],
    ['-t', serial, 'shell', 'bm', 'dump', '-n', BUNDLE],
  ]);
  assert.deepEqual(out.messages, ['PASS HarmonyOS API level 26', 'PASS Threads Harmony bundle installed',
    'SKIP UI smoke (add --ui on a dedicated demo target)']);
});

test('zero-exit HDC failures and missing installed bundle fail without disclosing stdout', async () => {
  for (const [api, bundle, expected] of [
    [`[Fail] target unavailable ${privateText}`, '', /FAIL API level query/],
    ['26', `error: bundle ${BUNDLE} not found ${privateText}`, /FAIL App bundle query/],
    ['26', JSON.stringify({ name: `${BUNDLE}.debug` }), /FAIL App bundle query/],
    ['26', JSON.stringify({ other: BUNDLE }), /FAIL App bundle query/],
  ]) {
    const out = capture();
    assert.equal(await main([...args, '--ui'], { ...out, execute(_file, argv, _opts, done) {
      done(null, argv[3] === 'param' ? api : bundle, privateText);
    } }), 1);
    assert.match(out.messages.at(-1), expected);
    assert.doesNotMatch(out.messages.join('\n'), new RegExp(`${privateText}|${serial}`));
  }
});

test('parses UI tree visibility, bounding boxes and wrappers without leaking invalid JSON', () => {
  const input = tree(
    node('hidden', { visible: 'false' }, [node('hidden-descendant')]),
    node('boolean-hidden', { visible: false }),
    node('zero-width', { bounds: '[1,1][1,999]' }),
    node('backward', { bounds: '[80,80][12,20]' }),
    node('bad', { bounds: 'extra:[0,1][99,100]' }),
    { children: [node('partly-visible', { bounds: '[-10,-1][18,8]', visible: 'true' })] },
  );
  assert.deepEqual(parseTree(`\uFEFF${input}`).map(({ id, rect }) => [id, rect]), [
    ['partly-visible', { left: -10, top: -1, right: 18, bottom: 8 }],
  ]);
  assert.equal(parseTree(JSON.stringify([node('array-root')]))[0].id, 'array-root');
  for (const invalid of [`{"attributes": ${privateText}}`, '{"children":[null]}', 'null']) {
    assert.throws(() => parseTree(invalid), error => !error.message.includes(privateText));
  }
});

test('receives a fresh scoped tree into a native absolute path and removes both temporary artifacts', async () => {
  const remotes = new Set();
  const locals = [];
  for (const mode of ['success', 'invalid-json', 'bad-receipt']) {
    const calls = [];
    let remote;
    let local;
    const result = dumpTree(async (_label, ...command) => {
      calls.push(command);
      if (command[2] === 'dumpLayout') {
        remote = command.at(-1);
        assert.match(remote, /^\/data\/local\/tmp\/threads-smoke-[a-f0-9-]{36}\.json$/);
        assert.ok(!remotes.has(remote));
        remotes.add(remote);
        assert.deepEqual(command, ['shell', 'uitest', 'dumpLayout', '-b', BUNDLE, '-a', '-p', remote]);
        return `DumpLayout saved to ${remote}`;
      }
      if (command[1] === 'recv') {
        local = command.at(-1);
        locals.push(local);
        assert.equal(command[2], remote);
        assert.ok(path.isAbsolute(local));
        if (process.platform === 'win32') assert.match(local, /^[A-Z]:\\/i);
        assert.equal(path.basename(local), path.posix.basename(remote));
        await writeFile(local, mode === 'invalid-json' ? privateText : tree(node('nav-home')));
        return mode === 'bad-receipt' ? `[Fail] ${privateText}` : 'FileTransfer finish';
      }
      assert.deepEqual(command, ['shell', 'rm', '-f', remote]);
      return '';
    });
    if (mode === 'success') assert.equal((await result)[0].id, 'nav-home');
    else await assert.rejects(result, error => /UI tree/.test(error.message) && !error.message.includes(privateText));
    assert.equal(calls.length, 3);
    await assert.rejects(stat(local), { code: 'ENOENT' });
    await assert.rejects(stat(path.dirname(local)), { code: 'ENOENT' });
  }
  assert.equal(new Set(locals).size, 3);
});

const navigation = (active) => [
  ...['home', 'search', 'activity', 'profile'].map((item, index) => node(`nav-${item}`, {
    bounds: `[${index * 100},250][${index * 100 + 80},290]`, selected: String(item === active),
  })),
  node('nav-compose'),
];
const homeTree = tree(...navigation('home'), node('home-feed'), node('', { text: 'Threads' }));
const discoveryTree = (...content) => tree(...navigation('search'), node('discovery-search'),
  node('', { text: '发现' }), node('', { text: privateText }), ...content);
const topicsTree = discoveryTree(node('discovery-topic-折叠屏', { bounds: '[0,70][80,110]' }));
const resultsTree = discoveryTree(
  node('__SearchField__discovery-search', { text: '折叠屏' }),
  node('discovery-clear-results', { bounds: '[70,0][130,80]' }),
  node('body-p3'),
  node('summary-p3', { bounds: '[0,130][80,180]' }),
);
const detailTree = (focused, id = 'convo-target-s4') => tree(
  node(id, { selected: focused }), node('convo-back', { bounds: '[0,0][50,60]' }), node('', { text: '帖子详情' }),
);

test('UI smoke uses fresh snapshots for the entire exact reply, return and clear flow', async () => {
  const stages = [homeTree, topicsTree, resultsTree, detailTree('true'), resultsTree, topicsTree, homeTree];
  const points = [['140', '270'], ['40', '90'], ['40', '155'], ['25', '30'], ['100', '40'], ['40', '270']];
  let step = 0;
  let captures = 0;
  const out = capture();
  await uiSmoke(async (_label, ...command) => {
    assert.deepEqual(command, ['shell', 'uitest', 'uiInput', 'click', ...points[step]]);
    assert.equal(captures, step + 1, 'each tap must be preceded by a fresh snapshot');
    step++;
    return '';
  }, out.log, { snapshot: async () => { captures++; return parseTree(stages[step]); }, pause: async () => {} });
  assert.equal(step, points.length);
  assert.equal(captures, stages.length);
  assert.equal(out.messages.length, 5);
  assert.match(out.messages.at(-1), /Clear search.*Home/);
  assert.doesNotMatch(out.messages.join('\n'), new RegExp(privateText));
});

test('UI smoke does not act on a duplicate nav target or an unselected/wrong reply', async () => {
  const cases = [
    { stages: [tree(...navigation('home'), node('home-feed'), node('', { text: 'Threads' }), node('nav-search'))],
      expected: /Home heading and navigation/ },
    { stages: [homeTree, discoveryTree(node('discovery-topic-折叠屏', { enabled: false }))], expected: /Discover topics/ },
    { stages: [homeTree, topicsTree, resultsTree, detailTree(false)], expected: /Exact demo reply focus/ },
    { stages: [homeTree, topicsTree, resultsTree, detailTree(true, 'convo-target-s3')], expected: /Exact demo reply focus/ },
    { stages: [homeTree, topicsTree, resultsTree, detailTree(true), topicsTree], expected: /Discover return preserves topic/ },
    { stages: [homeTree, topicsTree, resultsTree, detailTree(true), resultsTree, resultsTree],
      expected: /Clear search restores Discover topics/ },
  ];
  for (const { stages, expected } of cases) {
    let clicks = 0;
    let captures = 0;
    await assert.rejects(uiSmoke(async () => { clicks++; return ''; }, () => {}, {
      snapshot: async () => { captures++; return parseTree(stages[Math.min(clicks, stages.length - 1)]); },
      pause: async () => {},
    }), expected);
    assert.equal(clicks, stages.length - 1);
    assert.equal(captures, clicks + 5);
  }
});
