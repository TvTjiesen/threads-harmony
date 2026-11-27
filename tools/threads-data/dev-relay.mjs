import { createServer } from 'node:http';
import { pathToFileURL } from 'node:url';
import { createThreadsClient } from './meta-client.mjs';

const HOST = '127.0.0.1';
const PORT = 18948;
const PATH = '/v1/public-posts';
const MAX_TARGET = 8192;
const PARAMS = new Set(['mode', 'q', 'cursor']);
const FIELDS = ['id', 'username', 'text', 'permalink', 'timestamp', 'mediaType'];
const CONTROL = /[\u0000-\u001f\u007f-\u009f]/;
const MAX_RESPONSE_BYTES = 256 * 1024;
const STATUS = new Map([
  ['unconfigured', 503], ['invalid_input', 400], ['unauthorized', 401], ['permission', 403],
  ['rate_limited', 429], ['network', 502], ['upstream', 502], ['timeout', 504],
]);

function json(res, status, payload, extraHeaders) {
  if (res.destroyed) return;
  const body = JSON.stringify(payload);
  const size = Buffer.byteLength(body);
  if (size > MAX_RESPONSE_BYTES) return json(res, 502, { error: 'upstream' });
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': size,
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
    Connection: 'close',
    ...extraHeaders,
  });
  res.end(body);
}

function queryFrom(raw) {
  if (raw.length > MAX_TARGET || /[^\x21-\x7e]|#/.test(raw)) return null;
  try {
    const query = raw.slice(PATH.length + 1);
    decodeURIComponent(query); // URLSearchParams alone tolerates invalid percent escapes and UTF-8.
    const params = new URLSearchParams(query);
    const seen = new Set();
    for (const [name] of params) {
      if (!PARAMS.has(name) || seen.has(name)) return null;
      seen.add(name);
    }
    const mode = params.get('mode');
    const rawQ = params.get('q') ?? '';
    const q = rawQ.trim();
    const cursor = params.get('cursor') ?? '';
    if (CONTROL.test(rawQ) || !q ||
        (mode === 'search' ? rawQ.length > 200 :
          mode !== 'profile' || !/^@?[a-zA-Z0-9._]{1,30}$/.test(q)) ||
        (cursor && !/^[a-zA-Z0-9._~+/=-]{1,2048}$/.test(cursor))) return null;
    return { mode, q, cursor };
  } catch {
    return null;
  }
}

function projectPage(page) {
  if (!Array.isArray(page?.posts) || page.posts.length > 25 || typeof page.nextCursor !== 'string') return null;
  const posts = [];
  for (const post of page.posts) {
    if (!post || !FIELDS.every(field => typeof post[field] === 'string')) return null;
    posts.push(Object.fromEntries(FIELDS.map(field => [field, post[field]])));
  }
  return { posts, nextCursor: page.nextCursor };
}

export async function startDevRelay({ client, port = PORT, maxConcurrent = 2, upstreamTimeoutMs = 10_000 } = {}) {
  if (!Number.isInteger(port) || port < 0 || port > 65535 ||
      !Number.isSafeInteger(maxConcurrent) || maxConcurrent < 1 ||
      !Number.isInteger(upstreamTimeoutMs) || upstreamTimeoutMs < 1 || upstreamTimeoutMs > 2_147_483_647) {
    throw new TypeError('Invalid relay options.');
  }
  let inFlight = 0;

  async function handle(req, res) {
    const expectedHost = `${HOST}:${req.socket.localPort}`;
    if (req.headers.host !== expectedHost || req.headersDistinct.host?.length !== 1 ||
        Object.keys(req.headers).some(name => name === 'origin' || name === 'referer' || name.startsWith('sec-fetch-'))) {
      return json(res, 403, { error: 'permission' });
    }
    const target = req.url ?? '';
    if (target.split('?', 1)[0] !== PATH) return json(res, 404, { error: 'not_found' });
    if (req.method !== 'GET') return json(res, 405, { error: 'method_not_allowed' }, { Allow: 'GET' });
    if (req.headers.expect !== undefined || req.headers['transfer-encoding'] !== undefined ||
        (req.headers['content-length'] !== undefined && req.headers['content-length'] !== '0')) {
      return json(res, 400, { error: 'invalid_input' });
    }
    const input = queryFrom(target);
    if (!input) return json(res, 400, { error: 'invalid_input' });
    if (!client) return json(res, 503, { error: 'unconfigured' });
    if (inFlight >= maxConcurrent) return json(res, 429, { error: 'rate_limited' });

    const { mode, q, cursor } = input;
    const controller = new AbortController();
    const cancel = () => controller.abort();
    res.once('close', cancel);
    const stopped = new Promise((_, reject) => {
      controller.signal.addEventListener('abort', () => reject({ code: 'timeout' }), { once: true });
    });
    const timer = setTimeout(cancel, upstreamTimeoutMs);
    inFlight++;
    // Count actual upstream work until it settles, even when the client ignores abort.
    const task = Promise.resolve().then(() => mode === 'search'
      ? client.search(q, cursor, { signal: controller.signal })
      : client.profilePosts(q, cursor, { signal: controller.signal })).finally(() => { inFlight--; });
    try {
      const page = projectPage(await Promise.race([task, stopped]));
      return page ? json(res, 200, page) : json(res, 502, { error: 'upstream' });
    } catch (error) {
      const code = STATUS.has(error?.code) ? error.code : 'upstream';
      return json(res, STATUS.get(code), { error: code });
    } finally {
      clearTimeout(timer);
      res.off('close', cancel);
    }
  }

  const server = createServer({
    maxHeaderSize: 12 * 1024,
    headersTimeout: 5000,
    requestTimeout: 5000,
    connectionsCheckingInterval: 1000,
  });
  const respond = (req, res) => {
    void handle(req, res).catch(() => json(res, 502, { error: 'upstream' }));
  };
  server.on('request', respond);
  server.on('checkContinue', respond);
  server.on('checkExpectation', respond);
  server.maxHeadersCount = 0; // Check every header within maxHeaderSize, including duplicate Host and Origin.
  server.maxConnections = 32;
  server.setTimeout(12_000, socket => socket.destroy());
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen({ host: HOST, port }, () => {
      server.off('error', reject);
      resolve();
    });
  });
  return server;
}

const direct = import.meta.main ?? (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url);
if (direct) {
  const args = process.argv.slice(2);
  const port = args.length === 0 ? PORT :
    args.length === 2 && args[0] === '--port' && /^[1-9][0-9]{0,4}$/.test(args[1]) ? Number(args[1]) : 0;
  if (port < 1 || port > 65535) {
    console.error('Usage: node tools/threads-data/dev-relay.mjs [--port PORT]');
    process.exitCode = 1;
  } else {
    try {
      await startDevRelay({ port, client: createThreadsClient({ token: process.env.THREADS_ACCESS_TOKEN }) });
      console.log(`Threads development relay listening at http://${HOST}:${port}`);
    } catch {
      console.error('Unable to start the Threads development relay.');
      process.exitCode = 1;
    }
  }
}
