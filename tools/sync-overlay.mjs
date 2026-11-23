import { execFileSync } from 'node:child_process';
import { lstatSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const page = 'entry/src/main/ets/pages/Index.ets';
const target = `app/${page}`;

function file(path) {
  const absolute = join(root, path);
  if (!lstatSync(absolute).isFile() || relative(root, realpathSync(absolute)).replaceAll('\\', '/') !== path) {
    throw new Error(`Expected a regular project file: ${path}`);
  }
  return absolute;
}

function main(args) {
  if (args.length > 1 || (args.length === 1 && args[0] !== '--apply')) {
    throw new Error('Usage: node tools/sync-overlay.mjs [--apply]');
  }
  file('app/build-profile.json5');
  file('app/entry/src/main/module.json5');
  const destination = file(target);
  const source = readFileSync(file(`overlay/${page}`));
  if (source.equals(readFileSync(destination))) {
    console.log('Overlay already matches the Stage page.');
    return;
  }
  if (args.length === 0) {
    console.log(`Would replace ${target}. No files changed.`);
    return;
  }
  const options = { cwd: root, stdio: ['ignore', 'pipe', 'pipe'] };
  try {
    execFileSync('git', ['cat-file', '-e', `HEAD:${target}`], options);
  } catch {
    throw new Error(`Commit the template page before applying: ${target}`);
  }
  const status = execFileSync('git', ['status', '--porcelain=v1', '--', target], options);
  if (status.length !== 0) {
    throw new Error(`Commit or resolve local edits before replacing: ${target}`);
  }
  writeFileSync(destination, source);
  console.log(`Updated ${target}. Review the Git diff. Check INTERNET permission separately.`);
}

try {
  main(process.argv.slice(2));
} catch (error) {
  if (error.code === 'ENOENT' && error.path) {
    console.error(`Missing project file: ${relative(root, error.path)}. Create the Stage template in app/ first.`);
  } else {
    console.error(error.message);
  }
  process.exitCode = 1;
}
