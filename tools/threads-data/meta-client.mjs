// Endpoint paths follow Meta's fbsamples Threads Postman collection.
const GRAPH_ORIGIN = 'https://graph.threads.com';
const POST_FIELDS = 'id,username,text,permalink,timestamp,media_type';
const PAGE_SIZE = 25;
const MAX_BODY_BYTES = 256 * 1024;
const TIMEOUT_MS = 8_000;
const HANDLE = /^[a-zA-Z0-9._]{1,30}$/;
const POST_ID = /^[a-zA-Z0-9_-]{1,128}$/;
const CURSOR = /^[a-zA-Z0-9._~+/=-]{1,2048}$/;
const BEARER = /^[a-zA-Z0-9._~+/-]+=*$/;
const CONTROLS = /[\u0000-\u001f\u007f-\u009f]/;
const POST_HOSTS = new Set(['threads.com', 'www.threads.com', 'threads.net', 'www.threads.net']);
const RATE_CODES = new Set([4, 17, 32, 341, 613, 80000, 80001]);
const MESSAGES = Object.freeze({
  unconfigured: 'Threads access is not configured.',
  invalid_input: 'Invalid Threads request input.',
  unauthorized: 'Threads did not accept the access token.',
  permission: 'Threads denied permission for this request.',
  rate_limited: 'Threads is limiting requests. Try again later.',
  network: 'Could not reach Threads or the request timed out.',
  upstream: 'Threads returned an unexpected response.',
});

export class ThreadsDataError extends Error {
  constructor(code) {
    const safeCode = typeof code === 'string' && Object.hasOwn(MESSAGES, code) ? code : 'upstream';
    super(MESSAGES[safeCode]);
    this.name = 'ThreadsDataError';
    this.code = safeCode;
  }
}

function graphError(status, error) {
  const raw = error?.code;
  const code = typeof raw === 'string' && /^[0-9]{1,8}$/.test(raw) ? Number(raw) : raw;
  if (status === 429 || RATE_CODES.has(code)) return 'rate_limited';
  if (status === 401 || code === 102 || code === 190) return 'unauthorized';
  if (status === 403 || code === 10 || (Number.isInteger(code) && code >= 200 && code <= 299)) {
    return 'permission';
  }
  if (code === 100) return 'invalid_input';
  return 'upstream';
}

function discardBody(body) {
  if (!body) return;
  try {
    void body.cancel().catch(() => {});
  } catch {
    // Cancellation failures must not replace the public error.
  }
}

async function readJson(response, signal) {
  const body = response.body;
  const length = response.headers.get('content-length');
  if (length !== null && /^[0-9]+$/.test(length) && Number(length) > MAX_BODY_BYTES) {
    discardBody(body);
    throw new ThreadsDataError('upstream');
  }
  if (!body) throw new ThreadsDataError('upstream');

  const reader = body.getReader();
  const cancel = () => discardBody(reader);
  signal.addEventListener('abort', cancel, { once: true });
  let complete = false;
  try {
    const decoder = new TextDecoder('utf-8', { fatal: true });
    let bytes = 0;
    let text = '';
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > MAX_BODY_BYTES) throw new ThreadsDataError('upstream');
      text += decoder.decode(value, { stream: true });
    }
    complete = true;
    return JSON.parse(text + decoder.decode());
  } finally {
    signal.removeEventListener('abort', cancel);
    if (!complete) cancel();
    reader.releaseLock();
  }
}

function safePermalink(value, token) {
  if (typeof value !== 'string' || value.length > 2048 || /[\s\\]/.test(value) || CONTROLS.test(value)) {
    return '';
  }
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:' || !POST_HOSTS.has(url.hostname) || url.port || url.username || url.password ||
        !/^\/@[a-zA-Z0-9._]{1,30}\/post\/[a-zA-Z0-9_-]{1,128}\/?$/.test(url.pathname)) return '';
    const canonical = url.origin + url.pathname;
    return canonical.includes(token) ? '' : canonical;
  } catch {
    return '';
  }
}

function identity(value, token) {
  if (typeof value?.id !== 'string' || !POST_ID.test(value.id) || value.id.includes(token) ||
      typeof value.username !== 'string' || !HANDLE.test(value.username) || value.username.includes(token)) return null;
  return { id: value.id, username: value.username };
}

function postFrom(value, token) {
  const author = identity(value, token);
  if (!author) return null;
  return {
    ...author,
    text: typeof value.text === 'string' && !value.text.includes(token) ? value.text.slice(0, 4096) : '',
    permalink: safePermalink(value.permalink, token),
    timestamp: typeof value.timestamp === 'string' && value.timestamp.length <= 40 &&
      !CONTROLS.test(value.timestamp) && !value.timestamp.includes(token) && Number.isFinite(Date.parse(value.timestamp)) ?
      value.timestamp : '',
    mediaType: typeof value.media_type === 'string' && !value.media_type.includes(token) &&
      /^[A-Z][A-Z_]{0,31}$/.test(value.media_type) ? value.media_type : '',
  };
}

export function createThreadsClient({ token, fetchImpl = globalThis.fetch } = {}) {
  async function get(path, params, signal) {
    if (typeof token !== 'string' || token.length > 4096 || !BEARER.test(token) || typeof fetchImpl !== 'function') {
      throw new ThreadsDataError('unconfigured');
    }
    if ([params.q, params.username, params.after].some(value => value?.includes(token))) {
      throw new ThreadsDataError('invalid_input');
    }

    const url = new URL(path, GRAPH_ORIGIN);
    url.search = new URLSearchParams(params).toString();
    if (signal != null && !(signal instanceof AbortSignal)) throw new ThreadsDataError('invalid_input');
    if (signal?.aborted) throw new ThreadsDataError('network');
    const controller = new AbortController();
    let timer;
    let abort;
    const cancelled = new Promise((_, reject) => {
      abort = () => {
        reject(new ThreadsDataError('network'));
        controller.abort();
      };
      timer = setTimeout(abort, TIMEOUT_MS);
      signal?.addEventListener('abort', abort, { once: true });
    });

    async function request() {
      let response;
      try {
        response = await fetchImpl(url, {
          method: 'GET',
          headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
          redirect: 'error',
          credentials: 'omit',
          referrerPolicy: 'no-referrer',
          signal: controller.signal,
        });
      } catch {
        throw new ThreadsDataError('network');
      }
      if (!response || !Number.isInteger(response.status)) throw new ThreadsDataError('upstream');
      const { status } = response;
      if (controller.signal.aborted || response.redirected || response.type === 'opaqueredirect' ||
          (status >= 300 && status < 400) || (response.url && response.url !== url.href)) {
        discardBody(response.body);
        throw new ThreadsDataError('upstream');
      }
      let payload;
      try {
        payload = await readJson(response, controller.signal);
      } catch {
        throw new ThreadsDataError(graphError(status));
      }
      if (status < 200 || status >= 300 || payload?.error != null) {
        throw new ThreadsDataError(graphError(status, payload?.error));
      }
      return payload;
    }

    try {
      return await Promise.race([request(), cancelled]);
    } finally {
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
    }
  }

  async function page(path, params, cursor, signal) {
    if (typeof cursor !== 'string' || (cursor !== '' && !CURSOR.test(cursor))) {
      throw new ThreadsDataError('invalid_input');
    }
    const payload = await get(path, cursor ? { ...params, after: cursor } : params, signal);
    if (!Array.isArray(payload?.data)) throw new ThreadsDataError('upstream');
    const posts = payload.data.slice(0, PAGE_SIZE).map(value => postFrom(value, token)).filter(Boolean);
    const after = payload.paging?.cursors?.after;
    const nextCursor = typeof after === 'string' && CURSOR.test(after) && after !== cursor &&
      !after.includes(token) ? after : '';
    return { posts, nextCursor };
  }

  return {
    async search(query, cursor = '', options) {
      if (typeof query !== 'string' || query.length > 200 || CONTROLS.test(query) || !query.trim()) {
        throw new ThreadsDataError('invalid_input');
      }
      return page('/keyword_search', {
        q: query.trim(), search_type: 'RECENT', fields: POST_FIELDS, limit: String(PAGE_SIZE),
      }, cursor, options?.signal);
    },
    async profilePosts(username, cursor = '', options) {
      if (typeof username !== 'string' || username.length > 31 || CONTROLS.test(username)) {
        throw new ThreadsDataError('invalid_input');
      }
      const handle = username.trim().replace(/^@/, '');
      if (!HANDLE.test(handle)) throw new ThreadsDataError('invalid_input');
      return page('/profile_posts', { username: handle, fields: POST_FIELDS }, cursor, options?.signal);
    },
    async account(options) {
      const account = identity(await get('/me', { fields: 'id,username' }, options?.signal), token);
      if (!account) throw new ThreadsDataError('upstream');
      return account;
    },
  };
}
