import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const metrics = {
  'cold-first-present': {
    source: 'deveco-launch', unit: 'ms', scenarios: ['cold-launch'],
  },
  'process-pss': {
    source: 'hidumper-process', unit: 'kB',
    scenarios: ['home-idle', 'post-scroll', 'gallery-page-four', 'video-playing', 'post-resume'],
  },
};
const comparableKeys = ['schemaVersion', 'metric', 'source', 'unit', 'scenario', 'deviceClass',
  'osBuild', 'refreshHz', 'buildMode', 'collectorVersion'];
const fields = [...comparableKeys, 'revision', 'samples'];
const deviceClasses = ['phone-emulator', 'tablet-emulator', 'phone', 'foldable', 'tablet'];
const pssColumns = 'Pss Shared Shared Private Private Swap SwapPss Heap Heap Heap';
const pssLabels = 'Total Clean Dirty Clean Dirty Total Total Size Alloc Free';
const pssUnits = Array(10).fill('( kB )').join(' ');

export function parseProcessPss(text) {
  const lines = text.split(/\r?\n/).map((line) => line.trim().replace(/\s+/g, ' '));
  const sections = lines.flatMap((line, index) => /^-+\[memory\]-+$/.test(line) ? [index] : []);
  const headers = lines.flatMap((line, index) => line === pssColumns ? [index] : []);
  const [section] = sections;
  const [header] = headers;
  const rule = /^-{3,}$/;
  const fail = () => { throw new Error('Expected one supported HiDumper per-process PSS table with an unambiguous positive Total (kB).'); };
  if (sections.length !== 1 || headers.length !== 1 || header <= section ||
      lines.slice(section + 1, header).some(Boolean) ||
      lines[header + 1] !== pssLabels || lines[header + 2] !== pssUnits || !rule.test(lines[header + 3])) fail();

  const bottom = lines.findIndex((line, index) => index > header + 3 && rule.test(line));
  const totals = lines.filter((line) => /^Total(?:$| [+-]?\d)/.test(line));
  const total = lines[bottom + 1];
  if (bottom < header + 5 || lines.slice(header + 4, bottom).some((line) => !/^\S.*(?: \d+){10}$/.test(line)) ||
      totals.length !== 1 || total !== totals[0] || !/^Total(?: \d+){10}$/.test(total)) fail();

  const value = Number(total.split(' ')[1]);
  if (!Number.isSafeInteger(value) || value <= 0) fail();
  return value;
}

export function validateDataset(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data) ||
      Object.keys(data).length !== fields.length || !fields.every((key) => Object.hasOwn(data, key))) {
    throw new Error('Expected exactly the documented evidence fields; extra fields are not allowed.');
  }
  if (data.schemaVersion !== 1) throw new Error('Unsupported evidence schema version.');
  const spec = typeof data.metric === 'string' && Object.hasOwn(metrics, data.metric) ? metrics[data.metric] : null;
  if (!spec || data.source !== spec.source || data.unit !== spec.unit || !spec.scenarios.includes(data.scenario)) {
    throw new Error('Unsupported metric, source, unit, or scenario combination.');
  }
  if (!deviceClasses.includes(data.deviceClass) || typeof data.osBuild !== 'string' ||
      !/^\d{1,4}(?:\.\d{1,6}){2,4}$/.test(data.osBuild) ||
      !Number.isInteger(data.refreshHz) || data.refreshHz < 1 || data.refreshHz > 1000 ||
      !['debug', 'release'].includes(data.buildMode)) {
    throw new Error('Expected a supported device class, numeric OS build, refresh rate, and build mode.');
  }
  if (typeof data.collectorVersion !== 'string' ||
      (data.source === 'hidumper-process' ? data.collectorVersion !== 'os-bundled' :
        !/^\d{1,4}(?:\.\d{1,6}){2,4}$/.test(data.collectorVersion))) {
    throw new Error('Expected the documented collector version for this source.');
  }
  if (typeof data.revision !== 'string' || !/^[a-f0-9]{40}$/.test(data.revision)) {
    throw new Error('Expected a 40-character lowercase Git revision.');
  }
  if (!Array.isArray(data.samples) || !data.samples.length || !data.samples.every((value) => (
    Number.isFinite(value) && value > 0 && value <= Number.MAX_SAFE_INTEGER &&
    (data.metric !== 'process-pss' || Number.isSafeInteger(value))
  ))) {
    throw new Error('Expected nonempty positive samples in the declared unit (whole kB for PSS).');
  }
  return data;
}

export function summarize(data) {
  validateDataset(data);
  const sorted = [...data.samples].sort((a, b) => a - b);
  const count = sorted.length;
  const mid = Math.floor(count / 2);
  return {
    ...Object.fromEntries(comparableKeys.map((key) => [key, data[key]])),
    revision: data.revision,
    count,
    median: count % 2 ? sorted[mid] : sorted[mid - 1] + (sorted[mid] - sorted[mid - 1]) / 2,
    p95: sorted[Math.ceil(0.95 * count) - 1],
    smallSample: count < 20,
  };
}

export function compare(baseline, candidate) {
  const a = summarize(baseline);
  const b = summarize(candidate);
  const mismatch = [...comparableKeys, 'count'].filter((key) => a[key] !== b[key]);
  if (mismatch.length) throw new Error(`Not comparable: ${mismatch.join(', ')} must match.`);
  return { baseline: a, candidate: b, delta: { median: b.median - a.median, p95: b.p95 - a.p95 } };
}

const usage = `Usage:
  node tools/device-performance.mjs pss <dump.txt> [dump.txt ...]
  node tools/device-performance.mjs summarize <evidence.json>
  node tools/device-performance.mjs compare --matched-setup <baseline.json> <candidate.json>

Reads local files only. See docs/device-performance.md for collection and schema.`;

function readLocal(path, label) {
  try {
    return readFileSync(path, 'utf8').replace(/^\uFEFF/, '');
  } catch {
    throw new Error(`Cannot read ${label}.`);
  }
}

function readDataset(path, label) {
  const text = readLocal(path, label);
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`${label} is not valid JSON.`);
  }
}

function main([command, ...args]) {
  if (command === '--help' && !args.length) return console.log(usage);
  let result;
  if (command === 'pss' && args.length && !args.some((arg) => arg.startsWith('-'))) {
    if (new Set(args.map((path) => resolve(path))).size !== args.length) {
      throw new Error('Provide each dump file only once.');
    }
    result = args.map((path, index) => {
      const text = readLocal(path, `dump ${index + 1}`);
      try {
        return parseProcessPss(text);
      } catch (error) {
        throw new Error(`Dump ${index + 1}: ${error.message}`);
      }
    });
  } else if (command === 'summarize' && args.length === 1) {
    result = summarize(readDataset(args[0], 'Evidence file'));
  } else if (command === 'compare' && args.length === 3 && args[0] === '--matched-setup') {
    result = compare(readDataset(args[1], 'Baseline file'), readDataset(args[2], 'Candidate file'));
  } else {
    throw new Error(usage);
  }
  console.log(JSON.stringify(result, null, 2));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
