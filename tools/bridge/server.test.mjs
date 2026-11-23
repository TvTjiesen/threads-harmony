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
  await writeFile(join(tmp, 'bridge', 'state.json'), JSON.stringify({ schemaVersion: 1, jobs: { 'job-1234567890-deadbeef': { status: 'completed', worker: 'test-worker' } } }));
  const child = spawn(process.execPath, [join(clonedBridge, 'server.mjs'), '--host', '127.0.0.1', '--port', String(port)], {
    cwd: tmp, env: { ...process.env, BRIDGE_TOKEN: token }, stdio: 'ignore',
  });
  const base = `http://127.0.0.1:${port}`;
  try {
    let health;
    for (let i = 0; i < 60; i++) { try { health = await fetch(`${base}/health`); break; } catch { await delay(50); } }
    assert.equal(health?.status, 401);
    const queryToken = await fetch(`${base}/next?worker=test-worker&token=${encodeURIComponent(token)}`);
    assert.equal(queryToken.status, 401);
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
    assert.equal((await fetch(`${base}/next?worker=bad%20worker`, { headers })).status, 400);
    assert.equal(leasedJob.profile, 'doctor');
    assert.equal(leasedJob.steps[0].cmd, 'node --version');
    const wrongWorker = await fetch(`${base}/report`, { method: 'POST', headers, body: JSON.stringify({ jobId: leasedJob.id, status: 'ok', exitCode: 0, worker: 'other-worker' }) });
    assert.equal(wrongWorker.status, 409);
    const reported = await fetch(`${base}/report`, { method: 'POST', headers, body: JSON.stringify({ jobId: leasedJob.id, status: 'ok', exitCode: 0, worker: 'test-worker', stdout: 'safe report', injected: 'must not persist' }) });
    assert.equal(reported.status, 200);
    const storedReport = JSON.parse(await readFile(join(tmp, 'bridge', 'reports', `${leasedJob.id}.json`), 'utf8'));
    assert.equal(storedReport.stdout, 'safe report');
    assert.equal(Object.hasOwn(storedReport, 'injected'), false);
    assert.equal((await fetch(`${base}/bundle`, { headers })).status, 404);
    assert.equal((await fetch(`${base}/artifact?job=${leasedJob.id}&name=entry-default-unsigned.hap`, { method: 'POST', headers, body: 'not an artifact' })).status, 404);
    const expiredLeaseState = JSON.parse(await readFile(join(tmp, 'bridge', 'state.json'), 'utf8'));
    expiredLeaseState.jobs[leasedJob.id].status = 'running';
    expiredLeaseState.jobs[leasedJob.id].worker = 'test-worker';
    expiredLeaseState.jobs[leasedJob.id].leaseUntil = new Date(Date.now() - 1000).toISOString();
    await writeFile(join(tmp, 'bridge', 'state.json'), JSON.stringify(expiredLeaseState));
    const expiredReport = await fetch(`${base}/report`, { method: 'POST', headers, body: JSON.stringify({ jobId: leasedJob.id, status: 'ok', worker: 'test-worker' }) });
    assert.equal(expiredReport.status, 409);
    expiredLeaseState.jobs[leasedJob.id].leaseUntil = 'not-a-date';
    await writeFile(join(tmp, 'bridge', 'state.json'), JSON.stringify(expiredLeaseState));
    const malformedLeaseReport = await fetch(`${base}/report`, { method: 'POST', headers, body: JSON.stringify({ jobId: leasedJob.id, status: 'ok', worker: 'test-worker' }) });
    assert.equal(malformedLeaseReport.status, 409);
    expiredLeaseState.jobs[leasedJob.id].status = 'completed';
    await writeFile(join(tmp, 'bridge', 'state.json'), JSON.stringify(expiredLeaseState));
    const queryWithHeader = await fetch(`${base}/next?worker=test-worker&token=${encodeURIComponent(token)}`, { headers: { 'x-bridge-token': token } });
    assert.equal(queryWithHeader.status, 400);
    const noJob = await fetch(`${base}/next`, { headers: { 'x-bridge-token': token } });
    assert.equal(noJob.status, 204);
    const wrongHost = spawn(process.execPath, [join(clonedBridge, 'server.mjs'), '--host', '0.0.0.0', '--port', String(port + 1)], { cwd: tmp, env: { ...process.env, BRIDGE_TOKEN: token }, stdio: 'ignore' });
    const [wrongHostCode] = await once(wrongHost, 'exit');
    assert.equal(wrongHostCode, 1);
  } finally {
    child.kill(); await once(child, 'exit').catch(() => {});
    await rm(tmp, { recursive: true, force: true });
  }
});
