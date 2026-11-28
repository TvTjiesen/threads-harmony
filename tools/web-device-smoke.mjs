#!/usr/bin/env node
import { realpathSync } from 'node:fs';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { createHdc, dumpTree, parseArgs } from './device-smoke.mjs';

const HELP = `Usage: node tools/web-device-smoke.mjs --hdc <absolute executable> --serial <exact HDC target> --ui
       node tools/web-device-smoke.mjs --help

Only --ui contacts a device. Use an isolated, signed-out test emulator/device with the current
app foreground, unlocked on the root Profile tab (我的), and “打开 Threads 网页” visible.
The network sheet's “完成” button must be visible without scrolling. Any existing app proxy
is left unchanged; normal page loading may use it. Do not interact during the run.

Checks the native ArkWeb toolbar (including Back and Reload presence only), opens/closes
its network sheet, then uses Local Home to return to Profile. Entering ArkWeb can trigger
normal app loading; this is not a website or login check. No reload, external browser,
proxy, or system settings actions are performed. A temporary app-scoped UI tree may include
visible text; the smoke checks only native IDs/state/bounds and logs no raw tree/output or serial.
If interrupted or unsuccessful, return to Profile manually and check for temporary artifacts
if cleanup could not finish. No app launch or installation is performed.
`;

const WEB_ACTIONS = ['web-back', 'web-reload', 'web-settings', 'web-local-home'];
const DONE = 'web-settings-done';
const RETRIES = 5;
const SETTLE_MS = 250;
const commandFailed = output => /^\s*(?:\[fail\]|error\b|failed\b|fail:)/mi.test(output);

class WebSmokeError extends Error {}

function unique(nodes, id) {
  const matches = nodes.filter(node => node.id === id);
  return matches.length === 1 ? matches[0] : undefined;
}

function tapPoint(node) {
  if (!node?.rect || node.enabled === false || node.enabled === 'false') return undefined;
  const { left, top, right, bottom } = node.rect;
  const x = Math.floor(left + (right - left) / 2);
  const y = Math.floor(top + (bottom - top) / 2);
  return Number.isSafeInteger(x) && Number.isSafeInteger(y) && x >= 0 && y >= 0 ? [String(x), String(y)] : undefined;
}

function profile(nodes) {
  const selected = unique(nodes, 'nav-profile')?.selected;
  return (selected === true || selected === 'true') && tapPoint(unique(nodes, 'library-web')) &&
    !nodes.some(node => WEB_ACTIONS.includes(node.id) || node.id === DONE);
}

function toolbar(nodes) {
  return WEB_ACTIONS.every(id => tapPoint(unique(nodes, id)));
}

function sheetClosed(nodes) {
  return !nodes.some(node => node.id === DONE);
}

export async function uiSmoke(hdc, log, { snapshot = () => dumpTree(hdc), pause = delay } = {}) {
  async function expect(label, inspect) {
    for (let i = 0; i < RETRIES; i++) {
      if (i) await pause(SETTLE_MS);
      let nodes;
      try {
        nodes = await snapshot();
      } catch {
        throw new WebSmokeError(`${label}: app-scoped UI snapshot or temporary tree cleanup failed.`);
      }
      const result = inspect(nodes);
      if (result) return result;
    }
    throw new WebSmokeError(`${label}: expected unique, visible native controls on the prepared target.`);
  }

  async function click(label, id, state) {
    const point = await expect(label, nodes => state(nodes) && tapPoint(unique(nodes, id)));
    let output;
    try {
      output = await hdc(label, 'shell', 'uitest', 'uiInput', 'click', ...point);
    } catch {
      throw new WebSmokeError(`${label}: UITest click failed.`);
    }
    if (commandFailed(output)) throw new WebSmokeError(`${label}: UITest click failed.`);
    await pause(SETTLE_MS);
  }

  await click('Open Web from root Profile', 'library-web', profile);
  await click('ArkWeb native toolbar / open network sheet', 'web-settings', nodes => toolbar(nodes) && sheetClosed(nodes));
  log('PASS ArkWeb native toolbar actions visible from root Profile');
  // ArkUI may omit the underlying toolbar while the modal sheet is open.
  await click('Network sheet / Done', DONE, () => true);
  await click('Network sheet closed / Local Home', 'web-local-home', nodes => toolbar(nodes) && sheetClosed(nodes));
  log('PASS native network sheet opened and closed');
  await expect('Local Home returns to root Profile', profile);
  log('PASS Local Home returned to root Profile (native chrome only)');
}

export async function main(args, { log = console.log, error = console.error, execute } = {}) {
  if (args.length === 0) {
    log(HELP);
    return 0;
  }
  let options;
  try {
    options = parseArgs(args);
    if (!options.help && !options.ui) throw new WebSmokeError('--ui is required for device access.');
  } catch (err) {
    error(`Usage error: ${err.message} Run with --help.`);
    return 2;
  }
  if (options.help) {
    log(HELP);
    return 0;
  }
  try {
    await uiSmoke(createHdc(options, execute), log);
    return 0;
  } catch (err) {
    error(`FAIL ${err instanceof WebSmokeError ? err.message : 'Unexpected native chrome smoke error.'}`);
    return 1;
  }
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
  process.exitCode = await main(process.argv.slice(2));
}
