import { webview } from '@kit.ArkWeb';
import { url } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';

const HOME_URL: string = 'https://www.threads.com/';
const TOP_LEVEL_HOSTS: string[] = [
  'www.threads.com', 'threads.com', 'www.threads.net', 'threads.net',
  'www.instagram.com', 'instagram.com', 'accountscenter.facebook.com',
  'www.facebook.com', 'facebook.com', 'm.facebook.com', 'auth.meta.com'
];
const PREF_NAME: string = 'threads_settings';
const KEY_PROXY: string = 'proxy';

function isAllowedNavigation(target: string): boolean {
  try {
    const parsed = url.URL.parseURL(target);
    return parsed.protocol === 'https:' && parsed.username === '' && parsed.password === '' &&
      (parsed.port === '' || parsed.port === '443') && TOP_LEVEL_HOSTS.includes(parsed.hostname);
  } catch (_error) {
    return false;
  }
}

// 只接受 host[:port] 或 scheme://host[:port]，端口限定数字，拒绝任何路径/凭据。
function normalizeProxy(raw: string): string {
  const s = raw.trim();
  if (s.length === 0) {
    return '';
  }
  const m: RegExpMatchArray | null = s.match(/^(?:(https?|socks5?):\/\/)?([a-z0-9.-]+|\[[0-9a-f:]+\])(?::(\d{1,5}))?$/i);
  if (m === null) {
    return '';
  }
  const scheme: string = m[1] === null || m[1] === undefined ? 'http' : m[1].toLowerCase();
  const host: string = m[2];
  const port: string = m[3] === null || m[3] === undefined ? '' : m[3];
  if (port.length > 0) {
    const n: number = Number.parseInt(port, 10);
    if (n <= 0 || n > 65535) {
      return '';
    }
  }
  return port.length > 0 ? `${scheme}://${host}:${port}` : `${scheme}://${host}`;
}

@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  private prefs: preferences.Preferences | null = null;
  @State private busy: boolean = true;
  @State private banner: string = '';
  @State private proxyInput: string = '';
  @State private proxyActive: string = '';
  @State private showSettings: boolean = false;
  private loadAttempt: number = 0;

  aboutToAppear(): void {
    this.loadProxy();
  }

  private loadProxy(): void {
    try {
      const ctx = getContext(this) as Context;
      this.prefs = preferences.getPreferencesSync(ctx, { name: PREF_NAME });
      const saved = this.prefs.getSync(KEY_PROXY, '') as string;
      if (saved.length > 0) {
        this.proxyInput = saved;
        this.applyProxy(saved);
      }
    } catch (error) {
      const e = error as BusinessError;
      this.banner = `读取设置失败：${e.message}`;
    }
  }

  // ArkWeb 的应用级代理。API 15+；调用后所有 Web 组件共用，需等回调再加载页面。
  private applyProxy(raw: string): void {
    const rule = normalizeProxy(raw);
    if (rule.length === 0) {
      this.banner = '代理地址格式不对，应形如 192.168.1.10:7890';
      return;
    }
    try {
      const config = new webview.ProxyConfig();
      config.insertProxyRule(rule, webview.ProxySchemeFilter.MATCH_ALL_SCHEMES);
      webview.ProxyController.applyProxyOverride(config, () => {
        this.proxyActive = rule;
        this.proxyInput = rule;
        try {
          this.prefs?.putSync(KEY_PROXY, rule);
          this.prefs?.flush();
          this.banner = `代理已生效：${rule}`;
        } catch (error) {
          const e = error as BusinessError;
          this.banner = `代理已生效，但保存设置失败：${e.message}`;
        }
        this.reload();
      });
    } catch (error) {
      const e = error as BusinessError;
      this.banner = `代理设置失败（需要 API 15+）：${e.message}`;
    }
  }

  private saveProxy(): void {
    const rule = normalizeProxy(this.proxyInput);
    if (rule.length === 0) {
      this.banner = '地址格式不对，应形如 192.168.1.10:7890';
      return;
    }
    try {
      this.prefs?.putSync(KEY_PROXY, rule);
      this.prefs?.flush();
      this.proxyInput = rule;
      this.applyProxy(rule);
    } catch (error) {
      const e = error as BusinessError;
      this.banner = `保存失败：${e.message}`;
    }
  }

  private clearProxy(): void {
    try {
      this.prefs?.deleteSync(KEY_PROXY);
      this.prefs?.flush();
    } catch (_error) {
    }
    try {
      webview.ProxyController.removeProxyOverride(() => {
        this.proxyActive = '';
        this.proxyInput = '';
        this.banner = '代理已关闭';
        this.reload();
      });
    } catch (error) {
      const e = error as BusinessError;
      this.banner = `关闭代理失败：${e.message}`;
    }
  }

  private goBack(): boolean {
    try {
      if (this.controller.accessBackward()) {
        this.controller.backward();
        return true;
      }
    } catch (_error) {
      return false;
    }
    return false;
  }

  onBackPress(): boolean {
    if (this.showSettings) {
      this.showSettings = false;
      return true;
    }
    return this.goBack();
  }

  private startLoadWatchdog(): void {
    this.busy = true;
    const attempt = ++this.loadAttempt;
    setTimeout(() => {
      if (this.loadAttempt === attempt && this.busy) {
        this.busy = false;
        this.banner = '页面仍在加载。检查网络或代理设置后，可点右上角 ↻ 重试';
      }
    }, 20000);
  }

  private reload(): void {
    try {
      this.startLoadWatchdog();
      this.controller.loadUrl(HOME_URL);
    } catch (_error) {
      this.loadAttempt++;
      this.busy = false;
      this.banner = '页面还未就绪';
    }
  }

  private retry(): void {
    try {
      this.banner = '';
      this.startLoadWatchdog();
      this.controller.refresh();
    } catch (_error) {
      this.reload();
    }
  }

  @Builder
  SettingsPanel() {
    Column({ space: 12 }) {
      Text('网络代理').fontSize(18).fontWeight(FontWeight.Medium)
      Text('Threads 在国内无法直连。填入你电脑上代理软件监听在局域网的地址，例如 192.168.1.10:7890。仅本应用生效，不改变系统设置。')
        .fontSize(14)
        .fontColor('#666666')
      TextInput({ text: this.proxyInput, placeholder: '192.168.1.10:7890' })
        .onChange((v: string) => { this.proxyInput = v; })
        .width('100%')
      Row({ space: 8 }) {
        Button('保存并应用').onClick(() => { this.saveProxy(); }).layoutWeight(1)
        Button('关闭代理').onClick(() => { this.clearProxy(); }).layoutWeight(1)
      }.width('100%')
      if (this.proxyActive.length > 0) {
        Text(`当前生效：${this.proxyActive}`).fontSize(13).fontColor('#2a7d2a')
      }
      Button('返回').onClick(() => { this.showSettings = false; }).width('100%')
    }
    .width('100%')
    .padding(16)
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button('‹', { type: ButtonType.Normal })
          .fontSize(24)
          .width(48)
          .height(48)
          .accessibilityText('返回上一页')
          .onClick(() => { this.goBack(); })
        Text('Threads')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Button('⚙', { type: ButtonType.Normal })
          .fontSize(20)
          .width(48)
          .height(48)
          .accessibilityText('网络设置')
          .onClick(() => { this.showSettings = !this.showSettings; })
        Button('↻', { type: ButtonType.Normal })
          .fontSize(20)
          .width(48)
          .height(48)
          .accessibilityText('重新加载')
          .onClick(() => { this.retry(); })
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })

      if (this.showSettings) {
        this.SettingsPanel()
      }

      if (this.busy) {
        LoadingProgress().width(20).height(20).accessibilityText('加载中')
      }
      if (this.banner.length > 0) {
        Row({ space: 8 }) {
          Text(this.banner).fontSize(14).layoutWeight(1)
          Button('关闭').onClick(() => { this.banner = ''; })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 4 })
      }

      Web({ src: HOME_URL, controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(false)
        .mixedMode(MixedMode.None)
        .multiWindowAccess(false)
        .onLoadIntercept((event) => {
          if (event && event.data.isMainFrame() && !isAllowedNavigation(event.data.getRequestUrl())) {
            this.banner = '已拦截站外跳转';
            return true;
          }
          return false;
        })
        .onPageBegin(() => { this.startLoadWatchdog(); })
        .onPageEnd(() => {
          this.loadAttempt++;
          this.busy = false;
        })
        .onErrorReceive((event) => {
          if (event?.request.isMainFrame()) {
            this.loadAttempt++;
            this.busy = false;
            this.banner = this.proxyActive.length > 0
              ? '页面加载失败：检查代理连接后点 ↻ 重试'
              : '页面加载失败：如需代理，点 ⚙ 设置后再点 ↻ 重试';
          }
        })
    }
    .width('100%')
    .height('100%')
  }
}
