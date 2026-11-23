#!/usr/bin/env node
// 桥的本地命令行：添加任务 / 看回报。默认走 http://127.0.0.1:47921
//   node tools/bridge/cli.mjs add --title "跑构建" --cmd "cd ~/aitest/HarmonyLocalProbe && ./hvigorw assembleHap --no-daemon"
//   node tools/bridge/cli.mjs reports            # 列出已回报的任务
//   node tools/bridge/cli.mjs show <jobId>       # 看某次回报全文
//   node tools/bridge/cli.mjs health
import { readdir, readFile } from 'node:fs/promises';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..', '..');
const REPORTS = join(ROOT, 'bridge', 'reports');
const BASE = process.env.BRIDGE_URL || 'http://127.0.0.1:47921';

const [cmd, ...rest] = process.argv.slice(2);
const opt = (name, dflt) => {
  const i = rest.indexOf(name);
  return i >= 0 && rest[i + 1] ? rest[i + 1] : dflt;
};
const opts = (name) => rest.reduce((a, v, i) => (v === name && rest[i + 1] ? [...a, rest[i + 1]] : a), []);

async function main() {
  if (cmd === 'health') {
    console.log(await (await fetch(`${BASE}/health`)).text());
    return;
  }
  if (cmd === 'add') {
    const steps = opts('--cmd').map((c) => ({ cmd: c }));
    if (!steps.length) throw new Error('至少给一个 --cmd');
    const expect = opts('--expect');
    const r = await fetch(`${BASE}/jobs`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ title: opt('--title', 'untitled'), steps, expect }),
    });
    console.log(await r.text());
    return;
  }
  if (cmd === 'reports') {
    const files = (await readdir(REPORTS).catch(() => [])).filter((f) => f.endsWith('.json'));
    if (!files.length) return console.log('（还没有回报）');
    for (const f of files.sort()) {
      const r = JSON.parse(await readFile(join(REPORTS, f), 'utf8'));
      const head = String(r.stdout || '').trim().split('\n').slice(-1)[0] || '';
      console.log(`${f.replace(/\.json$/, '')}  status=${r.status ?? '?'} exit=${r.exitCode ?? '?'}  ${head.slice(0, 90)}`);
    }
    return;
  }
  if (cmd === 'show') {
    const id = rest[0];
    const r = JSON.parse(await readFile(join(REPORTS, `${id}.json`), 'utf8'));
    console.log(JSON.stringify(r, null, 2));
    return;
  }
  console.log('用法: health | add --title T --cmd C [--cmd C2] [--expect 正则] | reports | show <jobId>');
}

main().catch((e) => {
  console.error('ERR', e.message);
  process.exit(1);
});
