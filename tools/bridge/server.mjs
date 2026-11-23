#!/usr/bin/env node
// DSH <-> MatePad 双向消息桥。零依赖，只监听本机端口。
// 用法: node tools/bridge/server.mjs [--port 47921] [--host 0.0.0.0]
//
// 协议（全部 JSON）:
//   GET  /health                     -> {ok,time,pending,inFlight}
//   GET  /next?worker=<id>           -> 200 {job} | 204 空队列
//   POST /report                     -> {jobId,status,exitCode,stdout,stderr,notes,artifacts}
//   POST /artifact?job=<id>&name=<f> -> 原始字节（截图/log）落到 bridge/artifacts/
//   GET  /jobs                       -> 全部任务与状态
//   POST /jobs                       -> 追加任务，体 {title,kind,steps,expect}
import { createServer } from 'node:http';
import { mkdir, readdir, readFile, writeFile, rename } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..', '..');
const INBOX = join(ROOT, 'bridge', 'inbox');
const REPORTS = join(ROOT, 'bridge', 'reports');
const ARTIFACTS = join(ROOT, 'bridge', 'artifacts');

const argv = process.argv.slice(2);
const argOf = (name, dflt) => {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt;
};
const PORT = Number(argOf('--port', process.env.BRIDGE_PORT || 47921));
const HOST = argOf('--host', process.env.BRIDGE_HOST || '0.0.0.0');
const WORKER_TOKEN = process.env.BRIDGE_TOKEN || '';

const log = (...a) => console.log(new Date().toISOString(), ...a);
const safe = (s) => String(s).replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 120);

async function ensureDirs() {
  for (const d of [INBOX, REPORTS, ARTIFACTS]) await mkdir(d, { recursive: true });
}

const inflight = new Map(); // jobId -> {worker, at}
const delivered = new Set();

async function listJobs() {
  const files = (await readdir(INBOX)).filter((f) => f.endsWith('.json')).sort();
  const out = [];
  for (const f of files) {
    try {
      const j = JSON.parse(await readFile(join(INBOX, f), 'utf8'));
      j._file = f;
      j._delivered = delivered.has(j.id);
      out.push(j);
    } catch (e) {
      log('skip bad job', f, e.message);
    }
  }
  return out;
}

async function nextJob(worker) {
  const jobs = await listJobs();
  const job = jobs.find((j) => !delivered.has(j.id));
  if (!job) return null;
  delivered.add(job.id);
  inflight.set(job.id, { worker, at: Date.now() });
  log(`dispatch ${job.id} -> ${worker}`);
  return job;
}

function body(req, limit = 8 * 1024 * 1024) {
  return new Promise((res, rej) => {
    const chunks = [];
    let n = 0;
    req.on('data', (c) => {
      n += c.length;
      if (n > limit) {
        rej(new Error('body too large'));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => res(Buffer.concat(chunks)));
    req.on('error', rej);
  });
}

const json = (res, code, obj) => {
  const s = JSON.stringify(obj);
  res.writeHead(code, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(s),
  });
  res.end(s);
};

async function handle(req, res) {
  const url = new URL(req.url, 'http://x');
  const p = url.pathname;
  const auth = req.headers['x-bridge-token'] || url.searchParams.get('token');
  if (WORKER_TOKEN && auth !== WORKER_TOKEN && p !== '/health') {
    return json(res, 401, { error: 'bad token' });
  }

  if (req.method === 'GET' && p === '/health') {
    return json(res, 200, {
      ok: true,
      time: new Date().toISOString(),
      pending: (await listJobs()).filter((j) => !delivered.has(j.id)).length,
      inFlight: inflight.size,
    });
  }

  if (req.method === 'GET' && p === '/next') {
    const worker = url.searchParams.get('worker') || 'unknown';
    const job = await nextJob(worker);
    if (!job) {
      res.writeHead(204);
      return res.end();
    }
    return json(res, 200, { job });
  }

  if (req.method === 'POST' && p === '/report') {
    let payload;
    try {
      payload = JSON.parse((await body(req)).toString('utf8'));
    } catch (e) {
      return json(res, 400, { error: `bad json: ${e.message}` });
    }
    const id = safe(payload.jobId || `adhoc-${Date.now()}`);
    const file = join(REPORTS, `${id}.json`);
    const rec = { ...payload, receivedAt: new Date().toISOString() };
    await writeFile(file, JSON.stringify(rec, null, 2), 'utf8');
    inflight.delete(payload.jobId);
    log(`report ${id} status=${payload.status ?? '?'} exit=${payload.exitCode ?? '?'}`);
    if (payload.stdout) log('  stdout:', String(payload.stdout).slice(0, 400).replace(/\n/g, ' | '));
    if (payload.stderr) log('  stderr:', String(payload.stderr).slice(0, 400).replace(/\n/g, ' | '));
    return json(res, 200, { ok: true, saved: file });
  }

  if (req.method === 'POST' && p === '/artifact') {
    const job = safe(url.searchParams.get('job') || 'unscoped');
    const name = safe(url.searchParams.get('name') || `artifact-${Date.now()}`);
    const dir = join(ARTIFACTS, job);
    await mkdir(dir, { recursive: true });
    const buf = await body(req, 64 * 1024 * 1024);
    await writeFile(join(dir, name), buf);
    log(`artifact ${job}/${name} ${buf.length}B`);
    return json(res, 200, { ok: true, bytes: buf.length });
  }

  // 供 worker 的 sync 步骤拉取 overlay 源码（相对路径 -> 内容）
  if (req.method === 'GET' && p === '/bundle') {
    const files = [];
    const walk = async (dir) => {
      for (const e of await readdir(dir, { withFileTypes: true })) {
        const full = join(dir, e.name);
        if (e.isDirectory()) await walk(full);
        else if (e.isFile()) {
          const rel = full.slice(ROOT.length + 1).split('\\').join('/');
          if (/^(overlay|tools)\//.test(rel) && !rel.endsWith('.test.mjs')) {
            files.push({ path: rel, content: await readFile(full, 'utf8') });
          }
        }
      }
    };
    await walk(join(ROOT, 'overlay'));
    await walk(join(ROOT, 'tools'));
    return json(res, 200, { files });
  }

  if (req.method === 'GET' && p === '/jobs') {
    return json(res, 200, { jobs: await listJobs() });
  }

  if (req.method === 'POST' && p === '/jobs') {
    let payload;
    try {
      payload = JSON.parse((await body(req)).toString('utf8'));
    } catch (e) {
      return json(res, 400, { error: `bad json: ${e.message}` });
    }
    const job = {
      id: payload.id || `job-${Date.now()}-${randomUUID().slice(0, 6)}`,
      title: payload.title || 'untitled',
      kind: payload.kind || 'shell',
      steps: payload.steps || [],
      expect: payload.expect || [],
      createdAt: new Date().toISOString(),
    };
    await writeFile(join(INBOX, `${safe(job.id)}.json`), JSON.stringify(job, null, 2), 'utf8');
    log(`enqueue ${job.id} "${job.title}" steps=${job.steps.length}`);
    return json(res, 201, { ok: true, job });
  }

  json(res, 404, { error: 'not found' });
}

await ensureDirs();
const server = createServer((req, res) => {
  handle(req, res).catch((e) => {
    log('handler error', e.stack || e.message);
    try {
      json(res, 500, { error: e.message });
    } catch {}
  });
});
server.listen(PORT, HOST, () => {
  log(`bridge listening http://${HOST}:${PORT}`);
  log(`root=${ROOT}`);
});
