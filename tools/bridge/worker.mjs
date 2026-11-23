#!/usr/bin/env node
// 在 MatePad（CodeArts 的 CLT Node）上跑的执行器。粘一次、起一次，之后全靠轮询，人不用再动。
//
//   node worker.mjs --bridge http://10.62.244.233:47921 --root <工程目录>
//   node worker.mjs --doctor                 # 只打印环境事实，不领任务
//   node worker.mjs --once                   # 领一个任务就退（调试用）
//
// 任务步骤（server 端 /jobs 的 steps 数组）支持三种：
//   { "cmd": "cd $ROOT && ./hvigorw assembleHap --no-daemon" }
//   { "write": "entry/src/main/ets/pages/Index.ets", "content": "..." }
//   { "sync": true }                          # 从 bridge 拉 overlay/ 覆盖到 $ROOT
import { spawn } from 'node:child_process';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join, dirname } from 'node:path';

const argv = process.argv.slice(2);
const opt = (n, d) => {
  const i = argv.indexOf(n);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : d;
};
const flag = (n) => argv.includes(n);

const BRIDGE = opt('--bridge', process.env.BRIDGE_URL || 'http://127.0.0.1:47921').replace(/\/$/, '');
const ROOT = opt('--root', process.env.PROJECT_ROOT || process.cwd());
const WORKER = opt('--worker', `matepad-${Date.now().toString(36)}`);
const POLL = Number(opt('--poll', 3000));
const TOKEN = process.env.BRIDGE_TOKEN || '';
const COMMANDS_BY_PROFILE = {
  doctor: new Set(['node --version', 'ohpm -v', 'hvigorw --version', 'hdc -v', 'pwd', 'df -h .']),
  preflight: new Set(['pwd', 'node --version', 'hvigorw --version', 'test -f hvigorw && echo HVIGORW_OK', 'find entry/src/main -maxdepth 5 -type f | sort']),
  build: new Set(['hvigorw assembleHap --no-daemon -p product=default']),
};
const H = (extra = {}) => ({ ...(TOKEN ? { 'x-bridge-token': TOKEN } : {}), ...extra });

const say = (...a) => console.log(new Date().toISOString(), ...a);

function run(cmd, timeoutMs = 15 * 60 * 1000) {
  return new Promise((res) => {
    const started = Date.now();
    const child = spawn('sh', ['-c', `cd '${ROOT}' && ${cmd}`], { env: process.env });
    let out = '';
    let err = '';
    let killed = false;
    const t = setTimeout(() => {
      killed = true;
      child.kill('SIGKILL');
    }, timeoutMs);
    child.stdout.on('data', (d) => (out += d));
    child.stderr.on('data', (d) => (err += d));
    child.on('close', (code) => {
      clearTimeout(t);
      res({ exitCode: killed ? -1 : code, stdout: out, stderr: err, ms: Date.now() - started });
    });
    child.on('error', (e) =>
      res({ exitCode: -2, stdout: out, stderr: `${err}\nspawn error: ${e.message}`, ms: Date.now() - started })
    );
  });
}

async function doctor() {
  const probes = [
    ['node', 'node -v'],
    ['ohpm', 'ohpm -v'],
    ['hvigorw', 'ls hvigorw 2>/dev/null || echo MISSING'],
    ['hdc', 'hdc -v'],
    ['tar', 'tar --version 2>&1 | head -1'],
    ['root-ls', `ls -la '${ROOT}'`],
    ['disk', 'df -h . 2>/dev/null | tail -2'],
  ];
  const facts = {};
  for (const [k, c] of probes) {
    const r = await run(c, 30000);
    facts[k] = { exitCode: r.exitCode, out: (r.stdout + r.stderr).trim().slice(0, 800) };
    say(k, '=>', facts[k].out.split('\n')[0]);
  }
  const payload = { jobId: `doctor-${WORKER}`, status: 'ok', worker: WORKER, notes: 'environment probe', facts };
  const r = await fetch(`${BRIDGE}/report`, {
    method: 'POST',
    headers: H({ 'content-type': 'application/json' }),
    body: JSON.stringify(payload),
  });
  say('doctor report ->', r.status);
}

async function syncSources(jobId) {
  const r = await fetch(`${BRIDGE}/bundle`, { headers: H() });
  if (!r.ok) return { exitCode: -3, stdout: '', stderr: `bundle ${r.status}` };
  const { revision, files } = await r.json();
  const allowed = new Set(['overlay/entry/src/main/ets/pages/Index.ets', 'overlay/entry/src/main/module.json5']);
  let n = 0;
  for (const f of files) {
    if (!allowed.has(f.path)) throw new Error(`refusing unexpected bundle path: ${f.path}`);
    const dest = join(ROOT, f.path);
    await mkdir(dirname(dest), { recursive: true });
    await writeFile(dest, f.content, 'utf8');
    n++;
  }
  say(`synced ${n} files revision=${revision} into ${ROOT}`);
  return { exitCode: 0, stdout: `synced ${n} files revision=${revision}`, stderr: '' };
}

async function uploadArtifact(jobId, rel) {
  const allowed = new Set(['entry/build/default/outputs/default/entry-default-unsigned.hap']);
  if (!allowed.has(rel)) throw new Error(`refusing artifact path: ${rel}`);
  const p = join(ROOT, rel);
  if (!existsSync(p)) return null;
  const buf = await readFile(p);
  const name = rel.split('/').pop();
  const r = await fetch(`${BRIDGE}/artifact?job=${encodeURIComponent(jobId)}&name=${encodeURIComponent(name)}`, {
    method: 'POST',
    headers: H({ 'content-type': 'application/octet-stream' }),
    body: buf,
  });
  say(`artifact ${rel} -> ${r.status} (${buf.length}B)`);
  return r.ok ? { rel, bytes: buf.length } : null;
}

async function runJob(job, sendReport) {
  say(`job ${job.id} "${job.title}" (${job.steps.length} steps)`);
  const results = [];
  for (const step of job.steps) {
    if (step.sync) {
      results.push({ step: 'sync', ...(await syncSources(job.id)) });
    } else if (step.write) {
      results.push({ step: 'rejected', exitCode: -4, stdout: '', stderr: 'remote writes are disabled' });
      break;
    } else if (step.artifact) {
      if (job.profile !== 'build' || step.artifact !== 'entry/build/default/outputs/default/entry-default-unsigned.hap') {
        results.push({ step: 'rejected', exitCode: -5, stdout: '', stderr: 'artifact not allowed for this profile' });
        break;
      }
    } else if (step.cmd) {
      const allowedCommands = COMMANDS_BY_PROFILE[job.profile];
      if (!allowedCommands || !allowedCommands.has(step.cmd)) {
        results.push({ step: 'rejected', exitCode: -4, stdout: '', stderr: 'command not in local allowlist' });
        break;
      }
      say(`  $ ${step.cmd.slice(0, 160)}`);
      results.push({ step: step.cmd, ...(await run(step.cmd, step.timeoutMs)) });
    }
  }
  const failed = results.find((r) => r.exitCode !== 0);
  const artifacts = [];
  for (const step of job.steps) {
    if (step.artifact) {
      const a = await uploadArtifact(job.id, step.artifact);
      if (a) artifacts.push(a);
      else results.push({ step: `artifact ${step.artifact}`, exitCode: -5, stdout: '', stderr: 'artifact missing or upload failed' });
    }
  }
  const payload = {
    jobId: job.id,
    worker: WORKER,
    status: failed ? 'failed' : 'ok',
    exitCode: failed ? failed.exitCode : 0,
    failedStep: failed?.step,
    stdout: results.map((r) => `## ${r.step}\n${r.stdout}`).join('\n').slice(0, 200000),
    stderr: results.map((r) => `## ${r.step}\n${r.stderr}`).filter((s) => s.includes('\n') && s.split('\n')[1]).join('\n').slice(0, 200000),
    steps: results.map((r) => ({ step: r.step, exitCode: r.exitCode, ms: r.ms })),
    artifacts,
  };
  if (sendReport) {
    await sendReport(payload);
  } else {
    const r = await fetch(`${BRIDGE}/report`, {
      method: 'POST',
      headers: H({ 'content-type': 'application/json' }),
      body: JSON.stringify(payload),
    });
    say(`report ${job.id} -> ${r.status} status=${payload.status}`);
  }
  return payload;
}

async function main() {
  if (flag('--doctor')) return doctor();
  say(`worker ${WORKER} bridge=${BRIDGE} root=${ROOT}`);
  const once = flag('--once');

  // 中继模式：靠 ntfy 收任务、发回报，不需要两台设备同网段
  if (BRIDGE.startsWith('ntfy://')) {
    const { NtfyTransport } = await import('./transport.mjs');
    const relay = new NtfyTransport(BRIDGE.slice('ntfy://'.length));
    const seen = new Set();
    say('relay mode topic=' + relay.topic);
    for (;;) {
      let jobs = [];
      try {
        jobs = (await relay.poll()).filter((m) => m.kind === 'job' && !seen.has(m.id));
      } catch (e) {
        say('relay poll err:', e.message);
      }
      for (const job of jobs) {
        seen.add(job.id);
        const res = await runJob(job, async (payload) => {
          const r = await relay.publish('report', payload);
          say(`report ${job.id} -> relay ${r.status}`);
        });
        if (once) return res;
      }
      if (once && !jobs.length) return say('relay: 队列空');
      await new Promise((r) => setTimeout(r, POLL));
    }
  }

  for (;;) {
    let job = null;
    try {
      const r = await fetch(`${BRIDGE}/next?worker=${encodeURIComponent(WORKER)}&token=${encodeURIComponent(TOKEN)}`, {
        headers: H(),
      });
      if (r.status === 200) job = (await r.json()).job;
      else if (r.status !== 204) say('next ->', r.status);
    } catch (e) {
      say('bridge unreachable:', e.message);
    }
    if (job) await runJob(job);
    if (once) return;
    await new Promise((r) => setTimeout(r, POLL));
  }
}

main().catch((e) => {
  console.error('FATAL', e.stack || e.message);
  process.exit(1);
});
