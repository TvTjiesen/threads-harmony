#!/usr/bin/env node
// 回环任务执行器（仅供本机测试）。源码由 Git 交接，worker 不接受远程写入。
import { spawn } from 'node:child_process';

const argv = process.argv.slice(2);
const opt = (n, d) => {
  const i = argv.indexOf(n);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : d;
};
const flag = (n) => argv.includes(n);

const BRIDGE = opt('--bridge', process.env.BRIDGE_URL || 'http://127.0.0.1:47921').replace(/\/$/, '');
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
    const child = spawn('sh', ['-c', cmd], { cwd: ROOT, env: process.env });
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
    ['disk', 'df -h . 2>/dev/null | tail -2'],
  ];
  const facts = {};
  for (const [k, c] of probes) {
    const r = await run(c, 30000);
    facts[k] = { exitCode: r.exitCode, out: (r.stdout + r.stderr).trim().slice(0, 800) };
    say(k, '=>', facts[k].out.split('\n')[0]);
  }
  const payload = { jobId: `doctor-${WORKER}`, status: 'ok', worker: WORKER, notes: 'environment probe', facts };
  say('doctor mode is local-only; no report sent');
}

async function runJob(job, sendReport) {
  if (!job || !COMMANDS_BY_PROFILE[job.profile] || !Array.isArray(job.steps)) throw new Error('invalid job profile or steps');
  say(`job ${job.id} "${job.title}" (${job.steps.length} steps)`);
  const results = [];
  for (const step of job.steps) {
    if (!step || typeof step !== 'object' || Array.isArray(step)) {
      results.push({ step: 'rejected', exitCode: -6, stdout: '', stderr: 'invalid step shape' });
      break;
    }
    if (Object.hasOwn(step, 'sync') || Object.hasOwn(step, 'write')) {
      results.push({ step: 'rejected', exitCode: -4, stdout: '', stderr: 'remote writes are disabled' });
      break;
    } else if (Object.hasOwn(step, 'artifact')) {
      results.push({ step: 'rejected', exitCode: -5, stdout: '', stderr: 'artifact declaration invalid for this job' });
      break;
    } else if (step.cmd) {
      const allowedCommands = COMMANDS_BY_PROFILE[job.profile];
      if (!allowedCommands || !allowedCommands.has(step.cmd)) {
        results.push({ step: 'rejected', exitCode: -4, stdout: '', stderr: 'command not in local allowlist' });
        break;
      }
      say(`  $ ${step.cmd.slice(0, 160)}`);
      if (Object.keys(step).length !== 1) {
        results.push({ step: 'rejected', exitCode: -6, stdout: '', stderr: 'extra step properties are not allowed' });
        break;
      }
      results.push({ step: step.cmd, ...(await run(step.cmd)) });
      if (results.at(-1).exitCode !== 0) break;
    } else {
      results.push({ step: 'rejected', exitCode: -6, stdout: '', stderr: 'unknown step type' });
      break;
    }
  }
  const failed = results.find((r) => r.exitCode !== 0);
  const payload = {
    jobId: job.id,
    worker: WORKER,
    status: failed ? 'failed' : 'ok',
    exitCode: failed ? failed.exitCode : 0,
    failedStep: failed?.step,
    stdout: results.map((r) => `## ${r.step}\n${r.stdout}`).join('\n').slice(0, 200000),
    stderr: results.map((r) => `## ${r.step}\n${r.stderr}`).filter((s) => s.includes('\n') && s.split('\n')[1]).join('\n').slice(0, 200000),
    steps: results.map((r) => ({ step: r.step, exitCode: r.exitCode, ms: r.ms })),
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
  if (!TOKEN || TOKEN.length < 32) throw new Error('Set BRIDGE_TOKEN to a secret of at least 32 characters');
  if (!['http:', 'https:'].includes(new URL(BRIDGE).protocol)) throw new Error('Bridge URL must use HTTP or HTTPS');
  say(`worker ${WORKER} bridge=${BRIDGE}`);
  const once = flag('--once');

  // Deprecated relay path is disabled: anonymous topic is not an authenticated task channel.
  if (BRIDGE.startsWith('ntfy://')) throw new Error('ntfy relay mode is disabled; use authenticated HTTPS only');
  for (;;) {
    let job = null;
    try {
      const r = await fetch(`${BRIDGE}/next?worker=${encodeURIComponent(WORKER)}`, {
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
