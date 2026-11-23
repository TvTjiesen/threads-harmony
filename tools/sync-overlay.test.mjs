import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';

const page = 'entry/src/main/ets/pages/Index.ets';
const destination = `app/${page}`;

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'threads-overlay-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const put = (path, text) => {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), text);
  };
  put('tools/sync-overlay.mjs', '');
  copyFileSync(new URL('./sync-overlay.mjs', import.meta.url), join(root, 'tools/sync-overlay.mjs'));
  put(`overlay/${page}`, 'overlay page');
  const git = (...args) => execFileSync('git', args, { cwd: root, stdio: 'pipe' });
  git('init', '-q');
  const template = () => {
    put('app/build-profile.json5', '{}');
    put('app/entry/src/main/module.json5', '{ module: {} }');
    put(destination, 'template page');
  };
  const commit = () => {
    git('add', '--', 'app');
    git('-c', 'user.name=Overlay Test', '-c', 'user.email=overlay@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '-qm', 'Stage template fixture');
  };
  const run = (...args) => {
    const result = spawnSync(process.execPath, [join(root, 'tools/sync-overlay.mjs'), ...args], { cwd: tmpdir(), encoding: 'utf8' });
    if (result.error) throw result.error;
    return result;
  };
  return { commit, git, put, read: (path) => readFileSync(join(root, path), 'utf8'), run, template };
}

test('reports a missing Stage template', (t) => {
  const result = fixture(t).run();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Create the Stage template/);
});

test('preview leaves an uncommitted template untouched; apply refuses it', (t) => {
  const f = fixture(t);
  f.template();
  const preview = f.run();
  assert.equal(preview.status, 0);
  assert.match(preview.stdout, /No files changed/);
  const refused = f.run('--apply');
  assert.equal(refused.status, 1);
  assert.match(refused.stderr, /Commit the template page/);
  assert.equal(f.read(destination), 'template page');
});

test('apply protects worktree and staged edits', (t) => {
  const f = fixture(t);
  f.template();
  f.commit();
  f.put(destination, 'local edit');
  for (const staged of [false, true]) {
    if (staged) f.git('add', '--', destination);
    const result = f.run('--apply');
    assert.equal(result.status, 1);
    assert.match(result.stderr, /resolve local edits/);
    assert.equal(f.read(destination), 'local edit');
  }
});

test('apply only changes the clean Stage page and can be repeated', (t) => {
  const f = fixture(t);
  f.template();
  f.commit();
  assert.equal(f.run('--apply').status, 0);
  assert.equal(f.read(destination), 'overlay page');
  assert.equal(f.git('diff', '--name-only').toString().trim(), destination);
  const repeat = f.run('--apply');
  assert.equal(repeat.status, 0);
  assert.match(repeat.stdout, /already matches/);
});
