#!/usr/bin/env node
// 把 worker.mjs + transport.mjs 合成一个自包含文件，并生成 MatePad 上可直接粘贴的装载命令。
//
//   node tools/bridge/emit-worker.mjs                 # 打印装载命令
//   node tools/bridge/emit-worker.mjs --out w.mjs     # 只写单文件
//
// 为什么需要：MatePad 上不一定能 git clone，也不一定和 Windows 同网段。
// 单文件 + gzip + base64 后可以一行粘贴完成安装。
import { readFile, writeFile } from 'node:fs/promises';
import { gzipSync } from 'node:zlib';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..', '..');

const worker = await readFile(join(HERE, 'worker.mjs'), 'utf8');
const transport = await readFile(join(HERE, 'transport.mjs'), 'utf8');

// 去掉 transport 的 export 关键字，改成同文件内的声明，再插到 worker 顶部。
const inlined = transport
  .replace(/^export function /gm, 'function ')
  .replace(/^export class /gm, 'class ');

// worker 里对 transport 的 import 换成空（同文件已有定义）。
const body = worker
  .replace(/^#!.*\n/, '')
  .replace(/^import \{[^}]*\} from '\.\/transport\.mjs';\s*$/gm, '')
  .replace(/const \{ NtfyTransport \} = await import\('\.\/transport\.mjs'\);/g, '');

const combined = `#!/usr/bin/env node\n// 自动生成，勿手改。源：tools/bridge/worker.mjs + transport.mjs\n${inlined}\n${body}`;

const outIdx = process.argv.indexOf('--out');
if (outIdx > 0 && process.argv[outIdx + 1]) {
  await writeFile(resolve(process.argv[outIdx + 1]), combined, 'utf8');
  console.log(`written ${combined.length} bytes`);
  process.exit(0);
}

const gz = gzipSync(Buffer.from(combined, 'utf8'), { level: 9 });
const b64 = gz.toString('base64');
console.log(JSON.stringify({ source: combined.length, gzip: gz.length, base64: b64.length }, null, 2));
console.log('\n--- 把下面整行粘到 MatePad 的终端里（Terminal / HiShell / CodeArts 终端都行）---\n');
console.log(
  `mkdir -p ~/bridge && echo '${b64}' | base64 -d | gunzip > ~/bridge/worker.mjs && echo OK`
);
