#!/usr/bin/env node
// Restricted DSH <-> MatePad task bridge.
// Only fixed-profile tasks are accepted; no arbitrary shell command endpoint.
// Bind to loopback by default. Use a private tunnel to expose it remotely.
import { createServer } from 'node:http';
import { mkdir, readdir, readFile, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join, dirname, resolve, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID, timingSafeEqual, createHash } from 'node:crypto';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..', '..');
const BRIDGE_DIR = join(ROOT, 'bridge');
const INBOX = join(BRIDGE_DIR, 'inbox');
const REPORTS = join(BRIDGE_DIR, 'reports');
const ARTIFACTS = join(BRIDGE_DIR, 'artifacts');
const STATE = join(BRIDGE_DIR, 'state.json');
const argv = process.argv.slice(2);
const argOf = (name, fallback) => {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : fallback;
};
const PORT = Number(argOf('--port', process.env.BRIDGE_PORT || 47921));
const HOST = argOf('--host', process.env.BRIDGE_HOST || '127.0.0.1');
const TOKEN = process.env.BRIDGE_TOKEN || '';
const PROFILES = new Set(['doctor', 'preflight', 'build']);
const STALE_MS = 10 * 60 * 1000;
const log = (...args) => console.log(new Date().toISOString(), ...args);

if (!Number.isInteger(PORT) || PORT < 1 || PORT > 65535) throw new Error('invalid port');
if (!TOKEN || TOKEN.length < 32) throw new Error('Set BRIDGE_TOKEN to a random secret of at least 32 characters');
if (HOST === '0.0.0.0' && process.env.BRIDGE_ALLOW_PUBLIC !== 'yes') {
  throw new Error('Refusing 0.0.0.0 bind without BRIDGE_ALLOW_PUBLIC=yes; expose only behind an authenticated private tunnel');
}
const iso = () => new Date().toISOString();
const safeId = (s) => String(s || '').replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 120);
const json = (res, status, value) => {
  const body = JSON.stringify(value);
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'content-length': Buffer.byteLength(body), 'cache-control': 'no-store' });
  res.end(body);
};
function authorized(req) {
  const given = Buffer.from(String(req.headers['x-bridge-token'] || ''), 'utf8');
  const expected = Buffer.from(TOKEN, 'utf8');
  return given.length === expected.length && timingSafeEqual(given, expected);
}
function readBody(req, limit = 1024 * 1024) {
  return new Promise((resolveBody, reject) => {
    const chunks = []; let length = 0;
    req.on('data', (chunk) => {
      length += chunk.length;
      if (length > limit) { reject(new Error('body too large')); req.destroy(); return; }
      chunks.push(chunk);
    });
    req.on('end', () => resolveBody(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}
async function state() {
  try { return JSON.parse(await readFile(STATE, 'utf8')); }
  catch { return { schemaVersion: 1, jobs: {} }; }
}
async function saveState(s) {
  await mkdir(BRIDGE_DIR, { recursive: true });
  await writeFile(STATE, JSON.stringify(s, null, 2), 'utf8');
}
async function jobs() {
  await mkdir(INBOX, { recursive: true });
  const s = await state();
  const files = (await readdir(INBOX)).filter((name) => name.endsWith('.json')).sort();
  const all = [];
  for (const name of files) {
    try {
      const item = JSON.parse(await readFile(join(INBOX, name), 'utf8'));
      item.status = s.jobs[item.id]?.status || 'queued';
      item.leaseUntil = s.jobs[item.id]?.leaseUntil || null;
      all.push(item);
    } catch {}
  }
  return all;
}
const PROFILES_TASK = {
  doctor: { title: 'MatePad 工具链体检', kind: 'doctor', steps: [{ cmd: 'node --version' }, { cmd: 'ohpm -v' }, { cmd: 'hvigorw --version' }, { cmd: 'hdc -v' }, { cmd: 'pwd' }, { cmd: 'df -h .' }] },
  preflight: { title: 'Threads 工程只读预检', kind: 'preflight', steps: [{ cmd: 'pwd' }, { cmd: 'node --version' }, { cmd: 'hvigorw --version' }, { cmd: 'test -f hvigorw && echo HVIGORW_OK' }, { cmd: 'find entry/src/main -maxdepth 5 -type f | sort' }] },
  build: { title: 'Threads 工程构建', kind: 'build', steps: [{ cmd: 'hvigorw assembleHap --no-daemon -p product=default' }, { artifact: 'entry/build/default/outputs/default/entry-default-unsigned.hap' }] },
};
async function handle(req, res) {
  const url = new URL(req.url, 'http://localhost');
  if (!authorized(req)) return json(res, 401, { error: 'unauthorized' });
  if (req.method === 'GET' && url.pathname === '/health') {
    const list = await jobs();
    return json(res, 200, { ok: true, time: iso(), queued: list.filter((x) => x.status === 'queued').length, running: list.filter((x) => x.status === 'running').length });
  }
  if (req.method === 'GET' && url.pathname === '/next') {
    const worker = String(url.searchParams.get('worker') || 'matepad').slice(0, 80);
    const s = await state(); const list = await jobs();
    const candidate = list.find((item) => item.status === 'queued' || (item.status === 'running' && Date.parse(item.leaseUntil) < Date.now()));
    if (!candidate) { res.writeHead(204); return res.end(); }
    s.jobs[candidate.id] = { status: 'running', worker, leaseUntil: new Date(Date.now() + STALE_MS).toISOString(), updatedAt: iso() };
    await saveState(s);
    return json(res, 200, { job: candidate });
  }
  if (req.method === 'POST' && url.pathname === '/jobs') {
    const payload = JSON.parse((await readBody(req)).toString('utf8'));
    const profile = PROFILES_TASK[payload.profile];
    if (!profile) return json(res, 400, { error: 'profile must be one of doctor, preflight, build' });
    const id = `job-${Date.now()}-${randomUUID().slice(0, 8)}`;
    const job = { id, ...profile, profile: payload.profile, workspace: 'threads-harmony', createdAt: iso() };
    await mkdir(INBOX, { recursive: true }); await writeFile(join(INBOX, `${id}.json`), JSON.stringify(job, null, 2), { flag: 'wx' });
    return json(res, 201, { ok: true, job });
  }
  if (req.method === 'GET' && url.pathname === '/jobs') return json(res, 200, { jobs: await jobs() });
  if (req.method === 'POST' && url.pathname === '/report') {
    const report = JSON.parse((await readBody(req, 2 * 1024 * 1024)).toString('utf8'));
    if (!report.jobId || !['ok', 'failed'].includes(report.status)) return json(res, 400, { error: 'invalid report' });
    const id = safeId(report.jobId); const all = await jobs();
    if (!all.some((job) => job.id === report.jobId)) return json(res, 404, { error: 'unknown job' });
    const rec = { ...report, receivedAt: iso() };
    await mkdir(REPORTS, { recursive: true }); await writeFile(join(REPORTS, `${id}.json`), JSON.stringify(rec, null, 2), 'utf8');
    const s = await state(); s.jobs[id] = { ...(s.jobs[id] || {}), status: report.status, updatedAt: iso(), worker: report.worker || '' }; await saveState(s);
    log(`report ${id} status=${report.status} exit=${report.exitCode}`);
    return json(res, 200, { ok: true });
  }
  if (req.method === 'POST' && url.pathname === '/artifact') {
    const jobId = safeId(url.searchParams.get('job')); const name = safeId(url.searchParams.get('name'));
    if (!jobId || !name || !/^[\w.-]+$/.test(name)) return json(res, 400, { error: 'job and safe filename required' });
    const buf = await readBody(req, 64 * 1024 * 1024);
    const dir = join(ARTIFACTS, jobId); await mkdir(dir, { recursive: true }); const target = join(dir, name);
    await writeFile(target, buf);
    return json(res, 200, { ok: true, bytes: buf.length, sha256: createHash('sha256').update(buf).digest('hex') });
  }
  if (req.method === 'GET' && url.pathname === '/bundle') {
    const allowed = ['overlay/entry/src/main/ets/pages/Index.ets', 'overlay/entry/src/main/module.json5'];
    const files = [];
    for (const rel of allowed) {
      const file = join(ROOT, rel);
      if (existsSync(file)) files.push({ path: rel, content: await readFile(file, 'utf8') });
    }
    return json(res, 200, { revision: (await import('node:child_process')).execFileSync('git', ['rev-parse', 'HEAD'], { cwd: ROOT, encoding: 'utf8' }).trim(), files });
  }
  if (req.method === 'GET' && url.pathname === '/reports') return json(res, 200, { reports: (await readdir(REPORTS).catch(() => [])).filter((f) => f.endsWith('.json')) });
  return json(res, 404, { error: 'not found' });
}
await Promise.all([INBOX, REPORTS, ARTIFACTS].map((dir) => mkdir(dir, { recursive: true })));
const server = createServer((req, res) => handle(req, res).catch((error) => { log('handler error', error.stack || error.message); if (!res.headersSent) json(res, 500, { error: 'internal error' }); else res.destroy(); }));
server.listen(PORT, HOST, () => log(`restricted bridge listening http://${HOST}:${PORT}; profiles=${[...PROFILES].join(',')}`));
