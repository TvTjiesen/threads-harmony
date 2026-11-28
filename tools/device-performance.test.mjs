import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { compare, parseProcessPss, summarize, validateDataset } from './device-performance.mjs';

const script = fileURLToPath(new URL('./device-performance.mjs', import.meta.url));
const dump = (pss = 126685) => [
  '-------------------------------[memory]-------------------------------',
  '',
  '    Pss     Shared Shared Private Private Swap SwapPss Heap Heap Heap',
  '    Total   Clean Dirty Clean Dirty Total Total Size Alloc Free',
  `   ${Array(10).fill('( kB )').join('    ')}`,
  '                ------------------------------------------------------',
  '  native heap 43852 4888 6024 192 42924 22944 927 0 0 0',
  '----------------------------------------------------------------------',
  `     Total ${pss} 166728 30136 7280 93340 41932 1421 0 0 0`,
  '',
  'native heap:',
  '    jemalloc meta: 42 10 33 0 0 0 0 0 0 0',
  'Ashmem:',
  'Total Ashmem:144 kB',
  '',
].join('\r\n');
const evidence = (overrides = {}) => ({
  schemaVersion: 1, metric: 'process-pss', source: 'hidumper-process', unit: 'kB', scenario: 'home-idle',
  deviceClass: 'phone-emulator', osBuild: '7.0.0.107', refreshHz: 60, buildMode: 'debug',
  collectorVersion: 'os-bundled', revision: 'a'.repeat(40), samples: [124000, 128000, 125000, 126000], ...overrides,
});
const launch = (overrides = {}) => evidence({
  metric: 'cold-first-present', source: 'deveco-launch', unit: 'ms', scenario: 'cold-launch',
  collectorVersion: '26.0.1.290', samples: [751.8, 714.5, 720.1], ...overrides,
});

function fixture(t) {
  const dir = mkdtempSync(join(tmpdir(), 'threads-device-performance-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return {
    put(name, text) {
      const path = join(dir, name);
      writeFileSync(path, text);
      return path;
    },
    run(...args) {
      const result = spawnSync(process.execPath, [script, ...args], { cwd: dir, encoding: 'utf8' });
      if (result.error) throw result.error;
      return result;
    },
  };
}

test('selects only the aggregate PSS column, not swap, category or footer values', () => {
  assert.equal(parseProcessPss(dump()), 126685);
  assert.equal(parseProcessPss(dump().replaceAll('\r\n', '\n')), 126685);
});

test('rejects unsupported or ambiguous memory dump formats rather than guessing', () => {
  for (const text of [
    'hidumper: Permission denied',
    'PID Total Pss(xxx in SwapPss) Total Vss Total Rss Name\n1 4309(2216 in SwapPss) kB init',
    'Total 126685 166728 30136 7280 93340 41932 1421 0 0 0',
    dump().replace('Pss     Shared', 'Rss     Shared'),
    dump().replace('( kB )', '( MB )'),
    dump().replace('41932 1421 0 0 0', '41932 1421 0 0'),
    dump().replace('41932 1421 0 0 0', '41932 1421 unknown 0 0'),
    dump().replace('native heap 43852', 'Total 43852'),
    dump().replace('Ashmem:', 'Total 200 0 0 0 0 0 0 0 0 0\nAshmem:'),
    dump(0),
    dump(-1),
    dump('9,002'),
    dump('9007199254740992'),
    `${dump()}\n${dump()}`,
  ]) assert.throws(() => parseProcessPss(text), /unambiguous positive Total/);
});

test('summarizes sorted samples without mutating input, with nearest-rank P95 and small-n marker', () => {
  const data = evidence();
  assert.deepEqual(summarize(data), {
    schemaVersion: 1, metric: 'process-pss', source: 'hidumper-process', unit: 'kB', scenario: 'home-idle',
    deviceClass: 'phone-emulator', osBuild: '7.0.0.107', refreshHz: 60, buildMode: 'debug',
    collectorVersion: 'os-bundled', revision: 'a'.repeat(40), count: 4, median: 125500, p95: 128000,
    smallSample: true,
  });
  assert.deepEqual(data.samples, [124000, 128000, 125000, 126000]);
  const twenty = summarize(evidence({ samples: Array.from({ length: 20 }, (_, i) => 20 - i) }));
  assert.deepEqual([twenty.median, twenty.p95, twenty.smallSample], [10.5, 19, false]);
  assert.equal(summarize(launch()).median, 720.1);
  assert.equal(summarize(launch({ samples: [101.5] })).p95, 101.5);
});

test('only accepts explicit supported combinations, metadata and numeric values', () => {
  for (const data of [
    evidence({ schemaVersion: 2 }), evidence({ metric: '__proto__' }), evidence({ metric: ['process-pss'] }),
    evidence({ source: 'deveco-launch' }), evidence({ unit: 'KiB' }), evidence({ scenario: 'cold-launch' }),
    evidence({ osBuild: '7.0.0.107(SP-serial)' }), evidence({ refreshHz: '60' }), evidence({ buildMode: 'profile' }),
    evidence({ deviceClass: 'serial123' }), evidence({ revision: 'ab12' }), evidence({ collectorVersion: '1.0.0' }),
    launch({ source: 'hdc-host-elapsed' }), launch({ metric: 'ttfd' }), launch({ collectorVersion: 'unknown' }),
    evidence({ deviceSerial: 'private-value' }), evidence({ pid: 1234 }), evidence({ samples: [] }),
    evidence({ samples: [null] }), evidence({ samples: ['100'] }), evidence({ samples: [100.5] }),
    launch({ samples: [-1] }), launch({ samples: [Infinity] }), null, [],
  ]) assert.throws(() => validateDataset(data));
});

test('compares only like-for-like series and reports signed candidate-minus-baseline differences', () => {
  const base = evidence();
  const candidate = evidence({ revision: 'b'.repeat(40), samples: [120000, 122000, 125000, 130000] });
  assert.deepEqual(compare(base, candidate).delta, { median: -2000, p95: 2000 });
  for (const [key, value] of Object.entries({
    scenario: 'post-scroll', deviceClass: 'foldable', osBuild: '7.0.0.108', refreshHz: 120,
    buildMode: 'release', count: [1, 2, 3],
  })) {
    const change = key === 'count' ? { samples: value } : { [key]: value };
    assert.throws(() => compare(base, evidence(change)), new RegExp(key));
  }
  assert.throws(() => compare(base, launch()), /metric, source, unit/);
  assert.throws(() => compare(launch(), launch({ collectorVersion: '26.0.1.300' })), /collectorVersion/);
});

test('file CLI is offline and output does not echo raw identifiers or input paths', (t) => {
  const f = fixture(t);
  const raw1 = f.put('private-dump.txt', `\ufeff${dump()}\nprivate serial, pid, data`);
  const raw2 = f.put('next-dump.txt', dump(129000));
  const ok = f.run('pss', raw1, raw2);
  assert.equal(ok.status, 0, ok.stderr);
  assert.deepEqual(JSON.parse(ok.stdout), [126685, 129000]);
  assert.equal(ok.stderr, '');
  const duplicate = f.run('pss', raw1, raw1);
  assert.equal(duplicate.status, 1);
  assert.match(duplicate.stderr, /only once/);

  const malformed = f.put('private-id.txt', 'private serial');
  const bad = f.run('pss', raw1, malformed);
  assert.equal(bad.status, 1);
  assert.equal(bad.stdout, '');
  assert.match(bad.stderr, /Dump 2:/);
  assert.doesNotMatch(bad.stderr, /private-id|private serial/);

  const samples = f.put('evidence.json', `\ufeff${JSON.stringify(evidence())}`);
  const summary = f.run('summarize', samples);
  assert.equal(summary.status, 0, summary.stderr);
  assert.equal(JSON.parse(summary.stdout).median, 125500);
  const unknown = f.put('bad.json', JSON.stringify(evidence({ deviceSerial: 'secret-device' })));
  const badSummary = f.run('summarize', unknown);
  assert.equal(badSummary.status, 1);
  assert.doesNotMatch(badSummary.stderr, /secret-device|bad.json/);
  const newer = f.put('new.json', JSON.stringify(evidence({ revision: 'b'.repeat(40) })));
  const compareResult = f.run('compare', '--matched-setup', samples, newer);
  assert.equal(compareResult.status, 0, compareResult.stderr);
  assert.deepEqual(JSON.parse(compareResult.stdout).delta, { median: 0, p95: 0 });
  assert.equal(f.run('compare', samples, newer).status, 1);
});
