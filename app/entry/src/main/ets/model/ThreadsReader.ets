import { http } from '@kit.NetworkKit';

const RELAY_URL = 'http://127.0.0.1:18948/v1/public-posts';
const PAGE_LIMIT = 25;
const CURSOR_LIMIT = 2048;

export interface PublicPost {
  id: string;
  username: string;
  text: string;
  permalink: string;
  timestamp: string;
  mediaType: string;
}

export interface PublicPostPage {
  posts: PublicPost[];
  nextCursor: string;
  error: string;
}

interface RelayPage {
  posts?: PublicPost[];
  nextCursor?: string;
  error?: string;
}

function failed(error: string): PublicPostPage {
  return { posts: [], nextCursor: '', error: error };
}

export function isOfficialPostLink(link: string): boolean {
  return /^https:\/\/(www\.)?threads\.(com|net)\/@[A-Za-z0-9_.]{1,30}\/post\/[A-Za-z0-9_-]{1,100}\/?$/.test(link);
}

export function relayError(status: number, supplied: string): string {
  if (status === 400) { return '输入无效。'; }
  if (status === 401) { return 'Meta 授权已失效或未生效，请在开发主机重新授权。'; }
  if (status === 403) { return '当前 Meta 授权缺少对应的读取权限。'; }
  if (status === 429) { return '请求过于频繁，请稍后再试。'; }
  if (status === 503 && supplied === 'unconfigured') { return '开发中转已连接，但尚未配置 Meta 授权。'; }
  if (status === 504 || supplied === 'network') { return '开发中转暂时无法连接 Meta，请检查开发主机网络。'; }
  return '暂未取得官方响应，请稍后重试。';
}

export function decodeRelayPage(raw: string, status: number): PublicPostPage {
  if (raw.length > 262144) { return failed('返回内容过大，请稍后再试。'); }
  try {
    const value = JSON.parse(raw) as RelayPage;
    if (value === null || typeof value !== 'object') { return failed(relayError(status, '')); }
    if (status !== 200) { return failed(relayError(status, value.error ?? '')); }
    if (!Array.isArray(value.posts)) { return failed('返回内容格式不正确。'); }
    const posts: PublicPost[] = [];
    const seen = new Set<string>();
    for (const item of value.posts.slice(0, PAGE_LIMIT)) {
      if (item === null || typeof item !== 'object' || typeof item.id !== 'string' ||
        !/^[A-Za-z0-9_-]{1,120}$/.test(item.id) || seen.has(item.id) ||
        typeof item.username !== 'string' || !/^[A-Za-z0-9_.]{1,30}$/.test(item.username)) { continue; }
      seen.add(item.id);
      posts.push({ id: item.id, username: item.username,
        text: typeof item.text === 'string' ? item.text.slice(0, 4000) : '',
        permalink: typeof item.permalink === 'string' && isOfficialPostLink(item.permalink) ? item.permalink : '',
        timestamp: typeof item.timestamp === 'string' ? item.timestamp.slice(0, 40) : '',
        mediaType: typeof item.mediaType === 'string' ? item.mediaType.slice(0, 24) : '' });
    }
    const cursor = value.nextCursor;
    return { posts: posts, nextCursor: typeof cursor === 'string' && cursor.length <= CURSOR_LIMIT ? cursor : '', error: '' };
  } catch (_error) {
    return failed(status === 200 ? '返回内容格式不正确。' : relayError(status, ''));
  }
}

export async function requestThreadsPosts(query: string, byProfile: boolean, cursor: string): Promise<PublicPostPage> {
  const trimmed = query.trim();
  const q = byProfile ? trimmed.replace(/^@/, '') : trimmed;
  if (q.length === 0 || q.length > 120 || cursor.length > CURSOR_LIMIT ||
    (byProfile && !/^[A-Za-z0-9_.]{1,30}$/.test(q))) {
    return failed(byProfile ? '请输入完整的用户名，不是昵称。' : '请输入有效关键词。');
  }
  const request = http.createHttp();
  try {
    const target = `${RELAY_URL}?mode=${byProfile ? 'profile' : 'search'}&q=${encodeURIComponent(q)}` +
      (cursor.length > 0 ? `&cursor=${encodeURIComponent(cursor)}` : '');
    const response = await request.request(target, { method: http.RequestMethod.GET, header: { Accept: 'application/json' },
      usingProxy: false, usingCache: false, expectDataType: http.HttpDataType.STRING,
      maxRedirects: 0, maxLimit: 262144, connectTimeout: 3000, readTimeout: 12000 });
    return decodeRelayPage(typeof response.result === 'string' ? response.result : '', response.responseCode);
  } catch (_error) {
    return failed('无法连接开发中转。请先在 Windows 启动中转，并连接当前调试设备。');
  } finally {
    request.destroy();
  }
}
