#!/usr/bin/env node
import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { mkdtemp, readFile, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

export const BUNDLE = 'com.tvtjiesen.threadsharmony';
const TIMEOUT_MS = 15_000;
const MAX_TREE_BYTES = 8 * 1024 * 1024;
const TOPIC = '折叠屏';
const TOPIC_ID = `discovery-topic-${TOPIC}`;
const SEARCH_FIELD = '__SearchField__discovery-search';
const SEARCH_CANCEL = '__SearchField__CancelButton__discovery-search';
const NAV_IDS = ['nav-home', 'nav-search', 'nav-activity', 'nav-profile', 'nav-compose'];

const HELP = `Usage: node tools/device-smoke.mjs --hdc <absolute executable> --serial <exact HDC target> [--ui]
       node tools/device-smoke.mjs --help

Default: read the selected target's HarmonyOS API level and check that the app is installed.
--ui: also run the native Home → Discover topic → exact demo reply → Back → clear → Home flow.
      Use a dedicated demo device/emulator with the app already foreground on Home, no active
      Discover query, no matching local posts ahead of the demo and no local replies to demo p3.
      Keep the screen unlocked, the sample visible and do not interact during the run.
Only the app-scoped tree is pulled into a temporary file; no raw device output, tree, screenshot
or serial is logged. No launch, install, app data or settings changes, or app network requests.
On failure, return to Home and clear Discover manually before retrying. Unplugging or stopping
mid-run may prevent cleanup of a generated temporary tree.
`;

class SmokeError extends Error {}

function absoluteLocalPath(value, platform) {
  return platform === 'win32' ? /^[a-z]:[\\/]/i.test(value) : path.posix.isAbsolute(value);
}

export function parseArgs(args, platform = process.platform) {
  if (args.length === 1 && (args[0] === '--help' || args[0] === '-h')) return { help: true };
  const options = { ui: false };
  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--ui':
        if (options.ui) throw new SmokeError('--ui must not be repeated.');
        options.ui = true;
        break;
      case '--hdc':
        if (options.hdc !== undefined) throw new SmokeError('--hdc must not be repeated.');
        options.hdc = args[++i];
        if (!options.hdc || options.hdc.includes('\0') || !absoluteLocalPath(options.hdc, platform)) {
          throw new SmokeError('--hdc requires an absolute local executable path (drive-qualified on Windows).');
        }
        break;
      case '--serial':
        if (options.serial !== undefined) throw new SmokeError('--serial must not be repeated.');
        options.serial = args[++i];
        if (!/^[A-Za-z0-9][A-Za-z0-9_.:%\[\]-]{0,255}$/.test(options.serial ?? '')) {
          throw new SmokeError('--serial requires an exact HDC connection key.');
        }
        break;
      default:
        throw new SmokeError('Unknown argument.');
    }
  }
  if (!options.hdc || !options.serial) throw new SmokeError('--hdc and --serial are both required.');
  return options;
}

export function createHdc({ hdc, serial }, execute = execFile) {
  return (label, ...args) => new Promise((resolve, reject) => {
    execute(hdc, ['-t', serial, ...args], {
      encoding: 'utf8', timeout: TIMEOUT_MS, maxBuffer: 1024 * 1024, windowsHide: true, shell: false,
    }, (error, stdout, stderr) => {
      if (error || commandFailed(stderr ?? '')) {
        const reason = error?.killed ? 'timed out or was stopped' : 'failed';
        reject(new SmokeError(`${label}: HDC ${reason}. Check the executable and selected connection.`));
      } else {
        resolve(stdout.trim());
      }
    });
  });
}

const commandFailed = (output) => /^\s*(?:\[fail\]|error\b|failed\b|fail:)/mi.test(output);

function isBundleInstalled(output) {
  if (commandFailed(output)) return false;
  const jsonStart = output.indexOf('{');
  if (jsonStart < 0) return output.split(/\r?\n/).some(line => /^\s*bundleName\s*:/i.test(line) &&
    line.slice(line.indexOf(':') + 1).trim() === BUNDLE);
  try {
    const info = JSON.parse(output.slice(jsonStart));
    return [info.name, info.bundleName, info.appInfo?.name, info.appInfo?.bundleName].includes(BUNDLE);
  } catch {
    return false;
  }
}

export async function diagnostics(hdc, log) {
  const api = await hdc('API level query', 'shell', 'param', 'get', 'const.ohos.apiversion');
  if (!/^[1-9]\d{0,2}$/.test(api)) throw new SmokeError('API level query: expected a numeric HarmonyOS API level.');
  log(`PASS HarmonyOS API level ${api}`);
  const info = await hdc('App bundle query', 'shell', 'bm', 'dump', '-n', BUNDLE);
  if (!isBundleInstalled(info)) throw new SmokeError('App bundle query: expected Threads Harmony to be installed; bundle metadata could not confirm it.');
  log('PASS Threads Harmony bundle installed');
}

function bounds(value) {
  if (typeof value !== 'string') return undefined;
  const match = /^\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]$/.exec(value);
  if (!match) return undefined;
  const [left, top, right, bottom] = match.slice(1).map(Number);
  if (![left, top, right, bottom].every(Number.isSafeInteger) || right <= left || bottom <= top) return undefined;
  return { left, top, right, bottom };
}

export function parseTree(raw) {
  let root;
  try {
    root = JSON.parse(raw.replace(/^\uFEFF/, ''));
  } catch {
    throw new SmokeError('UI tree: invalid JSON.');
  }
  const pending = Array.isArray(root) ? [...root].reverse() : [root];
  const nodes = [];
  while (pending.length > 0) {
    const entry = pending.pop();
    if (!entry || typeof entry !== 'object' || Array.isArray(entry) ||
      (!entry.attributes && !Array.isArray(entry.children))) {
      throw new SmokeError('UI tree: unexpected hierarchy.');
    }
    const attr = entry.attributes;
    if (attr?.visible === false || attr?.visible === 'false') continue;
    const rect = bounds(attr?.bounds);
    if (rect) nodes.push({ ...attr, rect });
    if (entry.children !== undefined) {
      if (!Array.isArray(entry.children)) throw new SmokeError('UI tree: unexpected hierarchy.');
      for (let i = entry.children.length - 1; i >= 0; i--) pending.push(entry.children[i]);
    }
  }
  return nodes;
}

export async function dumpTree(hdc) {
  let dir;
  let failure;
  let cleanupFailed = false;
  const name = `threads-smoke-${randomUUID()}.json`;
  const remote = `/data/local/tmp/${name}`;
  try {
    dir = await mkdtemp(path.resolve(tmpdir(), 'threads-smoke-'));
    // HDC interprets a relative recv destination differently on Windows; pass a native absolute file path.
    const local = path.resolve(dir, name);
    if (!absoluteLocalPath(local, process.platform)) throw new SmokeError('UI tree: a drive-qualified local temp directory is required on Windows.');
    const dump = await hdc('UI tree dump', 'shell', 'uitest', 'dumpLayout', '-b', BUNDLE, '-a', '-p', remote);
    if (commandFailed(dump) || !dump.includes(remote)) throw new SmokeError('UI tree dump: could not capture the app window. Keep the app foreground and unlocked.');
    const receipt = await hdc('UI tree receive', 'file', 'recv', remote, local);
    if (commandFailed(receipt) || !receipt.includes('FileTransfer finish')) throw new SmokeError('UI tree receive: HDC did not confirm the transfer.');
    const info = await stat(local);
    if (!info.isFile() || info.size > MAX_TREE_BYTES) throw new SmokeError('UI tree receive: expected a bounded JSON file.');
    return parseTree(await readFile(local, 'utf8'));
  } catch (error) {
    failure = error instanceof SmokeError ? error : new SmokeError('UI tree: could not create or read the private local temporary file.');
    throw failure;
  } finally {
    if (dir) {
      try {
        const cleanup = await hdc('UI tree cleanup', 'shell', 'rm', '-f', remote);
        cleanupFailed = commandFailed(cleanup);
      } catch {
        cleanupFailed = true;
      }
      try {
        await rm(dir, { recursive: true, force: true });
      } catch {
        cleanupFailed = true;
      }
    }
    if (cleanupFailed) throw new SmokeError(`${failure ? `${failure.message} ` : ''}Temporary UI tree cleanup was not confirmed.`);
  }
}

const exactText = (node, text) => node.text === text || node.description === text;
const selected = (node) => node?.selected === true || node?.selected === 'true';

function unique(nodes, id) {
  const matches = nodes.filter(node => node.id === id);
  return matches.length === 1 ? matches[0] : undefined;
}

function clickPoint(node) {
  if (!node || node.enabled === false || node.enabled === 'false') return undefined;
  const { left, top, right, bottom } = node.rect;
  const x = Math.floor((left + right) / 2);
  const y = Math.floor((top + bottom) / 2);
  return x >= 0 && y >= 0 ? [String(x), String(y)] : undefined;
}

export async function uiSmoke(hdc, log, { snapshot = () => dumpTree(hdc), pause = delay } = {}) {
  async function expect(label, inspect) {
    for (let i = 0; i < 5; i++) {
      if (i > 0) await pause(250);
      const result = inspect(await snapshot());
      if (result) return result;
    }
    throw new SmokeError(`${label}: expected a unique, visible app control or state. Check the demo prerequisites.`);
  }

  async function click(label, inspect) {
    const point = await expect(label, nodes => clickPoint(inspect(nodes)));
    const output = await hdc(label, 'shell', 'uitest', 'uiInput', 'click', ...point);
    if (commandFailed(output)) throw new SmokeError(`${label}: UITest click failed.`);
    await pause(250);
  }

  function home(nodes) {
    return selected(unique(nodes, 'nav-home')) && unique(nodes, 'home-feed') &&
      NAV_IDS.every(id => unique(nodes, id)) && nodes.some(node => exactText(node, 'Threads'));
  }
  function discover(nodes) {
    return selected(unique(nodes, 'nav-search')) && unique(nodes, 'discovery-search') &&
      nodes.some(node => exactText(node, '发现'));
  }
  function topics(nodes) {
    return discover(nodes) && !nodes.some(node => node.id === SEARCH_CANCEL) && unique(nodes, TOPIC_ID);
  }
  function filtered(nodes) {
    return discover(nodes) && unique(nodes, SEARCH_FIELD)?.text === TOPIC && unique(nodes, 'body-p3') &&
      !nodes.some(node => node.id === TOPIC_ID);
  }

  await click('Home heading and navigation', nodes => home(nodes) && unique(nodes, 'nav-search'));
  log('PASS Home heading and navigation');
  await click('Discover topics', topics);
  await click('Discover topic result and reply summary', nodes => filtered(nodes) && unique(nodes, 'summary-p3'));
  log('PASS Discover topic and demo result');
  await click('Exact demo reply focus', nodes => selected(unique(nodes, 'convo-target-s4')) &&
    nodes.some(node => exactText(node, '帖子详情')) && unique(nodes, 'convo-back'));
  log('PASS Exact demo reply selected in conversation detail');
  await click('Discover return preserves topic', nodes => filtered(nodes) && unique(nodes, 'discovery-clear-results'));
  log('PASS Discover return preserves topic');
  await click('Clear search restores Discover topics', nodes => topics(nodes) && unique(nodes, 'nav-home'));
  await expect('Return to Home', home);
  log('PASS Clear search restores Discover topics and returns to Home');
}

export async function main(args, { log = console.log, error = console.error, execute } = {}) {
  let options;
  try {
    options = parseArgs(args);
  } catch (err) {
    error(`Usage error: ${err instanceof SmokeError ? err.message : 'Invalid arguments.'} Run with --help.`);
    return 2;
  }
  if (options.help) {
    log(HELP);
    return 0;
  }
  const hdc = createHdc(options, execute);
  try {
    await diagnostics(hdc, log);
    if (options.ui) await uiSmoke(hdc, log);
    else log('SKIP UI smoke (add --ui on a dedicated demo target)');
    return 0;
  } catch (err) {
    error(`FAIL ${err instanceof SmokeError ? err.message : 'Unexpected smoke error.'}`);
    return 1;
  }
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
  process.exitCode = await main(process.argv.slice(2));
}
