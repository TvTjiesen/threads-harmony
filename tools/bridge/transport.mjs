// 传输层：LAN 直连 或 ntfy.sh 中继。两边共用，靠 URL 前缀选。
//   http://10.x.x.x:47921    局域网直连（同一 Wi-Fi/校园网，最省事）
//   ntfy://<topic>           ntfy.sh 中继（两台设备都能出公网即可，不需要同网段）
//
// ntfy 单条消息有限制，超出时自动切块发送、对端自动拼回，调用方无感。
const NTFY = (topic) => `https://ntfy.sh/${encodeURIComponent(topic)}`;
const MAX_RELAY = 3500; // 单条上限（留出头部余量）
const CHUNK = 2400; // 分块大小

export function parseTarget(raw) {
  if (raw.startsWith('ntfy://')) return { kind: 'ntfy', topic: raw.slice('ntfy://'.length).replace(/\/$/, '') };
  return { kind: 'http', base: raw.replace(/\/$/, '') };
}

export class HttpTransport {
  constructor(base, token = '') {
    this.base = base;
    this.token = token;
  }
  headers(extra = {}) {
    return { ...(this.token ? { 'x-bridge-token': this.token } : {}), ...extra };
  }
  async post(path, obj) {
    const r = await fetch(this.base + path, {
      method: 'POST',
      headers: this.headers({ 'content-type': 'application/json' }),
      body: JSON.stringify(obj),
    });
    return { status: r.status, text: await r.text() };
  }
  async getJson(path) {
    const r = await fetch(this.base + path, { headers: this.headers() });
    if (r.status === 204) return null;
    if (!r.ok) throw new Error(`${path} -> ${r.status}`);
    return r.json();
  }
  async postBytes(path, buf) {
    const r = await fetch(this.base + path, {
      method: 'POST',
      headers: this.headers({ 'content-type': 'application/octet-stream' }),
      body: buf,
    });
    return { status: r.status, text: await r.text() };
  }
}

// ntfy 中继：发布/轮询。topic 名自带随机串，充当弱口令；不要用于敏感内容。
export class NtfyTransport {
  constructor(topic) {
    this.topic = topic;
    this.lastId = '';
    this._buf = new Map(); // ref -> { total, parts: Map<seq, string> }
    this._done = new Set(); // 已拼完并投递过的 ref
  }

  async _post(body, title) {
    const r = await fetch(NTFY(this.topic), {
      method: 'POST',
      headers: { 'content-type': 'text/plain', Title: title },
      body,
    });
    if (!r.ok) throw new Error(`ntfy ${r.status}`);
    return r.status;
  }

  async publish(kind, payload) {
    const body = JSON.stringify({ kind, ...payload });
    const ref = String(payload?.id || `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`);
    if (body.length <= MAX_RELAY) return { status: await this._post(body, `${kind}-${ref}`), chunks: 1 };

    const total = Math.ceil(body.length / CHUNK);
    for (let i = 0; i < total; i++) {
      const env = JSON.stringify({ kind: '__chunk', ref, seq: i, total, data: body.slice(i * CHUNK, (i + 1) * CHUNK) });
      await this._post(env, `chunk-${ref}-${i}`);
    }
    return { status: 200, chunks: total };
  }

  async poll(since) {
    const q = since ? `&since=${encodeURIComponent(since)}` : '&since=all';
    const ctl = AbortSignal.timeout(20000);
    const r = await fetch(`${NTFY(this.topic)}/json?poll=1${q}`, { signal: ctl });
    const text = await r.text();
    const events = text
      .split('\n')
      .filter(Boolean)
      .map((l) => {
        try {
          return JSON.parse(l);
        } catch {
          return null;
        }
      })
      .filter((e) => e && e.event === 'message');

    const out = [];
    for (const e of events) {
      let obj;
      try {
        obj = JSON.parse(e.message || '{}');
      } catch {
        continue;
      }
      if (obj && obj.kind === '__chunk') {
        const buf = this._buf.get(obj.ref) || { total: obj.total, parts: new Map() };
        buf.total = obj.total;
        buf.parts.set(obj.seq, obj.data);
        this._buf.set(obj.ref, buf);
        if (buf.parts.size >= buf.total && !this._done.has(obj.ref)) {
          const full = [];
          for (let i = 0; i < buf.total; i++) full.push(buf.parts.get(i) || '');
          let reassembled = null;
          try {
            reassembled = JSON.parse(full.join(''));
          } catch {
            reassembled = null;
          }
          this._done.add(obj.ref);
          this._buf.delete(obj.ref);
          if (reassembled) out.push({ id: e.id, ...reassembled });
        }
        continue;
      }
      if (obj) out.push({ id: e.id, ...obj });
    }
    return out;
  }
}
