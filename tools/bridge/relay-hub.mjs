#!/usr/bin/env node
// Windows 侧中继 hub：给「MatePad 和 Windows 不在同一网段」时用。
// 任务通过 ntfy.sh 发出，MatePad 的 worker 领走执行，回报再被这里收回来落盘。
//
//   node tools/bridge/relay-hub.mjs add --title "构建" --cmd "cd \$ROOT && ./hvigorw assembleHap --no-daemon"
//   node tools/bridge/relay-hub.mjs collect --watch
//   node tools/bridge/relay-hub.mjs reports
//
// 环境变量 BRIDGE_RELAY=ntfy://<topic>。topic 自带随机串当弱口令，别放敏感内容。
import { mkdir, writeFile, readdir, readFile } from 'node:fs/promises';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseTarget, NtfyTransport } from './transport.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..', '..');
const REPORTS = join(ROOT, 'bridge', 'reports');
const STATE = join(ROOT, 'bridge', 'relay-state.json');

const target = process.env.BRIDGE_RELAY || '';
const [cmd, ...rest] = process.argv.slice(2);
const opt = (n, d) => {
  const i = rest.indexOf(n);
  return i >= 0 && rest[i + 1] ? rest[i + 1] : d;
};
const opts = (n) => rest.reduce((a, v, i) => (v === n && rest[i + 1] ? [...a, rest[i + 1]] : a), []);

if (!target) {
  console.error('缺少 BRIDGE_RELAY=ntfy://<topic>');
  process.exit(1);
}
const t = parseTarget(target);
if (t.kind !== 'ntfy') {
  console.error('relay-hub 只处理 ntfy://；局域网请直接用 server.mjs');
  process.exit(1);
}
const relay = new NtfyTransport(t.topic);

async function loadState() {
  try {
    return JSON.parse(await readFile(STATE, 'utf8'));
  } catch {
    return { lastId: '' };
  }
}
const saveState = async (s) => {
  await mkdir(dirname(STATE), { recursive: true });
  await writeFile(STATE, JSON.stringify(s, null, 2), 'utf8');
};

async function main() {
  if (cmd === 'add') {
    const steps = opts('--cmd').map((c) => ({ cmd: c }));
    if (!steps.length) throw new Error('至少一个 --cmd');
    const job = {
      id: `job-${Date.now()}`,
      title: opt('--title', 'untitled'),
      steps,
      artifacts: opts('--artifact'),
    };
    const r = await relay.publish('job', job);
    console.log(JSON.stringify({ ok: r.status === 200, job, relayStatus: r.status }, null, 2));
    return;
  }

  if (cmd === 'collect') {
    const watch = rest.includes('--watch');
    for (;;) {
      const st = await loadState();
      const msgs = await relay.poll(st.lastId || undefined).catch((e) => {
        console.error('poll err', e.message);
        return [];
      });
      for (const m of msgs) {
        if (m.kind === 'report') {
          const id = String(m.jobId || `relay-${m.id}`);
          await writeFile(join(REPORTS, `${id.replace(/[^\w.-]/g, '_')}.json`), JSON.stringify(m, null, 2), 'utf8');
          console.log(`report ${id} status=${m.status} exit=${m.exitCode}`);
          const tail = String(m.stdout || '').trim().split('\n').slice(-3).join(' | ');
          if (tail) console.log('   ', tail.slice(0, 200));
        } else if (m.kind === 'job') {
          console.log(`(seen job ${m.id} — 这是自己发的，忽略)`);
        }
        st.lastId = m.id;
      }
      await saveState(st);
      if (!watch) return;
      await new Promise((r) => setTimeout(r, 4000));
    }
  }

  if (cmd === 'reports') {
    const files = (await readdir(REPORTS).catch(() => [])).filter((f) => f.endsWith('.json')).sort();
    if (!files.length) return console.log('（还没有回报）');
    for (const f of files) {
      const r = JSON.parse(await readFile(join(REPORTS, f), 'utf8'));
      console.log(`${f.replace(/\.json$/, '')}  status=${r.status} exit=${r.exitCode}`);
    }
    return;
  }

  console.log('用法: add --title T --cmd C | collect [--watch] | reports');
}

main().catch((e) => {
  console.error('ERR', e.message);
  process.exit(1);
});
