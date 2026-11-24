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
const LOAD_TIMEOUT_MS: number = 20000;

function isAllowedNavigation(target: string): boolean {
  try {
    const parsed = url.URL.parseURL(target);
    return parsed.protocol === 'https:' && parsed.username === '' && parsed.password === '' &&
      (parsed.port === '' || parsed.port === '443') && TOP_LEVEL_HOSTS.includes(parsed.hostname.toLowerCase());
  } catch (_error) {
    return false;
  }
}

// ArkWeb ProxyConfig accepts [scheme://]host[:port], not paths or credentials.
function normalizeProxy(raw: string): string {
  const value = raw.trim();
  if (value.length === 0) {
    return '';
  }
  const match: RegExpMatchArray | null = value.match(/^(?:(https?|socks):\/\/)?([a-z0-9.-]+|\[[0-9a-f:]+\])(?::(\d{1,5}))?$/i);
  if (match === null) {
    return '';
  }
  const scheme: string = match[1] === null || match[1] === undefined ? 'http' : match[1].toLowerCase();
  const host: string = match[2];
  const port: string = match[3] === null || match[3] === undefined ? '' : match[3];
  if (port.length > 0) {
    const number: number = Number.parseInt(port, 10);
    if (number <= 0 || number > 65535) {
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
  @State private webReady: boolean = false;
  private loadPending: boolean = false;
  private loadAttempt: number = 0;
  private proxyAttempt: number = 0;

  aboutToAppear(): void {
    try {
      const context = getContext(this) as Context;
      this.prefs = preferences.getPreferencesSync(context, { name: PREF_NAME });
      const saved = this.prefs.getSync(KEY_PROXY, '') as string;
      if (saved.length > 0) {
        this.proxyInput = saved;
        this.applyProxy(saved, true);
        return;
      }
    } catch (error) {
      const reason = error as BusinessError;
      this.banner = `读取网络设置失败：${reason.message}`;
    }
    this.loadHome();
  }

  private applyProxy(raw: string, fromSaved: boolean = false): void {
    const rule = normalizeProxy(raw);
    if (rule.length === 0) {
      this.banner = '代理地址格式不对，应为 主机名或IP:端口';
      if (fromSaved) {
        this.loadHome();
      }
      return;
    }
    try {
      const config = new webview.ProxyConfig();
      config.insertProxyRule(rule);
      const attempt = ++this.proxyAttempt;
      this.banner = '正在应用代理…';
      webview.ProxyController.applyProxyOverride(config, () => {
        if (attempt !== this.proxyAttempt) {
          return;
        }
        this.proxyActive = rule;
        this.proxyInput = rule;
        try {
          this.prefs?.putSync(KEY_PROXY, rule);
          this.prefs?.flush();
          this.banner = '代理已生效';
        } catch (error) {
          const reason = error as BusinessError;
          this.banner = `代理已生效，但保存失败：${reason.message}`;
        }
        this.loadHome();
      });
      setTimeout(() => {
        if (attempt === this.proxyAttempt && this.proxyActive !== rule) {
          this.proxyAttempt++;
          this.banner = '等待代理应用超时。检查设置后可重试，或关闭代理直连';
          if (fromSaved) {
            this.proxyInput = '';
          }
          this.loadHome();
        }
      }, LOAD_TIMEOUT_MS);
    } catch (error) {
      this.proxyAttempt++;
      const reason = error as BusinessError;
      this.banner = `代理设置失败：${reason.message}`;
      if (fromSaved) {
        this.proxyInput = '';
        this.loadHome();
      }
    }
  }

  private saveProxy(): void {
    const rule = normalizeProxy(this.proxyInput);
    if (rule.length === 0) {
      this.banner = '代理地址格式不对，应为 主机名或IP:端口';
      return;
    }
    if (rule !== this.proxyActive) {
      this.banner = '正在应用代理…';
    }
    this.applyProxy(rule);
  }

  private clearProxy(): void {
    try {
      const attempt = ++this.proxyAttempt;
      webview.ProxyController.removeProxyOverride(() => {
        if (attempt !== this.proxyAttempt) {
          return;
        }
        this.proxyActive = '';
        this.proxyInput = '';
        try {
          this.prefs?.deleteSync(KEY_PROXY);
          this.prefs?.flush();
        } catch (error) {
          const reason = error as BusinessError;
          this.banner = `代理已关闭，但删除保存项失败：${reason.message}`;
        }
        this.banner = '代理已关闭';
        this.loadHome();
      });
    } catch (error) {
      const reason = error as BusinessError;
      this.banner = `关闭代理失败：${reason.message}`;
    }
  }

  private loadHome(): void {
    if (!this.webReady) {
      this.loadPending = true;
      return;
    }
    this.loadPending = false;
    try {
      const attempt = ++this.loadAttempt;
      this.busy = true;
      this.controller.loadUrl(HOME_URL);
      setTimeout(() => {
        if (this.loadAttempt === attempt && this.busy) {
          this.busy = false;
          this.banner = '页面仍在加载，请检查网络/代理后点 ↻ 重试';
          this.controller.stop();
        }
      }, LOAD_TIMEOUT_MS);
    } catch (_error) {
      this.loadAttempt++;
      this.busy = false;
      this.banner = '页面尚未就绪，请点 ↻ 重试';
    }
  }

  private retry(): void {
    this.banner = '';
    this.loadHome();
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

  @Builder
  SettingsPanel() {
    Column({ space: 12 }) {
      Text('网络代理').fontSize(18).fontWeight(FontWeight.Medium)
      Text('可填写电脑代理在局域网开放的地址，例如 192.168.1.10:7890。需与平板连同一网络，并在代理软件开启局域网访问。只作用于本应用。')
        .fontSize(14).fontColor('#666666')
      TextInput({ text: this.proxyInput, placeholder: '192.168.1.10:7890' })
        .onChange((value: string) => { this.proxyInput = value; })
        .width('100%')
      Row({ space: 8 }) {
        Button('保存并应用').onClick(() => { this.saveProxy(); }).layoutWeight(1)
        Button('关闭代理').onClick(() => { this.clearProxy(); }).layoutWeight(1)
      }.width('100%')
      if (this.proxyActive.length > 0) {
        Text('代理已配置').fontSize(13).fontColor('#2a7d2a')
      }
      Button('返回').onClick(() => { this.showSettings = false; }).width('100%')
    }
    .width('100%')
    .padding(16)
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button('‹', { type: ButtonType.Normal }).fontSize(24).width(48).height(48)
          .accessibilityText('返回上一页').onClick(() => { this.goBack(); })
        Text('Threads').fontSize(18).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('⚙', { type: ButtonType.Normal }).fontSize(20).width(48).height(48)
          .accessibilityText('网络设置').onClick(() => { this.showSettings = !this.showSettings; })
        Button('↻', { type: ButtonType.Normal }).fontSize(20).width(48).height(48)
          .accessibilityText('重新加载').onClick(() => { this.retry(); })
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

      Web({ src: 'about:blank', controller: this.controller })
        .width('100%').layoutWeight(1)
        .javaScriptAccess(true).domStorageAccess(true).fileAccess(false)
        .mixedMode(MixedMode.None).multiWindowAccess(false)
        .onControllerAttached(() => {
          this.webReady = true;
          if (this.loadPending || this.proxyInput.length === 0 || this.proxyActive.length > 0) {
            this.loadHome();
          }
        })
        .onLoadIntercept((event) => {
          if (!event || !event.data.isMainFrame()) {
            return false;
          }
          const target = event.data.getRequestUrl();
          if (target === 'about:blank') {
            return false;
          }
          if (!isAllowedNavigation(target)) {
            this.banner = '已拦截站外跳转';
            return true;
          }
          return false;
        })
        .onPageBegin((event) => {
          if (event.url !== 'about:blank') {
            this.busy = true;
            this.banner = '';
          }
        })
        .onPageEnd((event) => {
          if (event.url !== 'about:blank') {
            this.loadAttempt++;
            this.busy = false;
          }
        })
        .onErrorReceive((event) => {
          if (event.request.isMainFrame()) {
            this.loadAttempt++;
            this.busy = false;
            this.banner = this.proxyActive.length > 0
              ? '页面加载失败：检查代理连接后点 ↻ 重试'
              : '页面加载失败：可检查网络或在 ⚙ 中设置代理';
          }
        })
        .onHttpErrorReceive((event) => {
          if (event.request.isMainFrame()) {
            this.loadAttempt++;
            this.busy = false;
            this.banner = `网页响应异常（${event.response.getResponseCode()}），可点 ↻ 重试`;
          }
        })
        .onPermissionRequest((event) => { event.request.deny(); })
        .onSslErrorEventReceive((event) => { event.handler.handleCancel(); })
    }
    .width('100%').height('100%')
  }
}
