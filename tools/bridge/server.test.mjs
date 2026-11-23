import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as delay } from 'node:timers/promises';
import { mkdtemp, rm, readFile, writeFile, mkdir } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { createServer } from 'node:net';
import { fileURLToPath } from 'node:url';

async function freePort() {
  const s = createServer(); s.listen(0, '127.0.0.1'); await once(s, 'listening'); const p = s.address().port; await new Promise((r) => s.close(r)); return p;
}

test('bridge auth, fixed profile enqueue/lease/report; rejects arbitrary shell', async () => {
  const source = dirname(fileURLToPath(import.meta.url));
  const tmp = await mkdtemp(join(tmpdir(), 'threads-bridge-test-'));
  const port = await freePort();
  const token = 'test-secret-token-longer-than-32-bytes';
  const clonedTools = join(tmp, 'tools');
  const clonedBridge = join(clonedTools, 'bridge');
  await mkdir(clonedBridge, { recursive: true });
  await writeFile(join(clonedBridge, 'server.mjs'), await readFile(join(source, 'server.mjs')));
  await mkdir(join(tmp, 'bridge', 'inbox'), { recursive: true });
  await writeFile(join(tmp, 'bridge', 'inbox', 'job-1234567890-deadbeef.json'), JSON.stringify({ id: 'job-1234567890-deadbeef', profile: 'doctor', steps: [{ cmd: 'touch pwned' }] }));
  const child = spawn(process.execPath, [join(clonedBridge, 'server.mjs'), '--host', '127.0.0.1', '--port', String(port)], {
    cwd: tmp, env: { ...process.env, BRIDGE_TOKEN: token }, stdio: 'ignore',
  });
  const base = `http://127.0.0.1:${port}`;
  try {
    let health;
    for (let i = 0; i < 60; i++) { try { health = await fetch(`${base}/health`); break; } catch { await delay(50); } }
    assert.equal(health?.status, 401);
    const headers = { 'x-bridge-token': token, 'content-type': 'application/json' };
    const reject = await fetch(`${base}/jobs`, { method: 'POST', headers, body: JSON.stringify({ profile: 'unsafe', steps: [{ cmd: 'whoami' }] }) });
    assert.equal(reject.status, 400);
    const extraFields = await fetch(`${base}/jobs`, { method: 'POST', headers, body: JSON.stringify({ profile: 'doctor', title: 'run arbitrary command' }) });
    assert.equal(extraFields.status, 400);
    const accepted = await fetch(`${base}/jobs`, { method: 'POST', headers, body: JSON.stringify({ profile: 'doctor' }) });
    assert.equal(accepted.status, 201);
    const job = (await accepted.json()).job;
    assert.equal(job.profile, 'doctor');
    assert.equal(job.steps[0].cmd, 'node --version');
    assert.notEqual(job.steps[0].cmd, 'touch pwned');
    const leased = await fetch(`${base}/next?worker=test-worker`, { headers: { 'x-bridge-token': token } });
    assert.equal(leased.status, 200);
    const leasedJob = (await leased.json()).job;
    assert.equal(leasedJob.profile, 'doctor');
    assert.equal(leasedJob.steps[0].cmd, 'node --version');
    const reported = await fetch(`${base}/report`, { method: 'POST', headers, body: JSON.stringify({ jobId: leasedJob.id, status: 'ok', exitCode: 0, worker: 'test-worker' }) });
    assert.equal(reported.status, 200);
    const secondLease = await fetch(`${base}/next`, { headers: { 'x-bridge-token': token } });
    assert.equal(secondLease.status, 200);
    const secondJob = (await secondLease.json()).job;
    assert.equal(secondJob.id, job.id);
    assert.equal(secondJob.steps[0].cmd, 'node --version');
    const secondReport = await fetch(`${base}/report`, { method: 'POST', headers, body: JSON.stringify({ jobId: secondJob.id, status: 'ok', exitCode: 0, worker: 'test-worker' }) });
    assert.equal(secondReport.status, 200);
    const noJob = await fetch(`${base}/next`, { headers: { 'x-bridge-token': token } });
    assert.equal(noJob.status, 204);
  } finally {
    child.kill(); await once(child, 'exit').catch(() => {});
    await rm(tmp, { recursive: true, force: true });
  }
});
