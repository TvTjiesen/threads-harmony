import { webview } from '@kit.ArkWeb';
import { url } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { router } from '@kit.ArkUI';

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
  private loadAttempt: number = 0;
  private startupPaused: boolean = true;
  @State private proxyPending: boolean = false;

  private initializeNetwork(): void {
    let saved: preferences.ValueType = '';
    try {
      const context = getContext(this) as Context;
      this.prefs = preferences.getPreferencesSync(context, { name: PREF_NAME });
      saved = this.prefs.getSync(KEY_PROXY, '');
    } catch (_error) {
      this.busy = false;
      this.banner = '读取网络设置失败。请在 ⚙ 中重新选择代理或关闭代理。';
      return;
    }
    if (saved === '') {
      this.startupPaused = false;
      this.loadHome();
      return;
    }
    const rule: string = typeof saved === 'string' ? normalizeProxy(saved) : '';
    if (rule.length === 0) {
      const removed = this.persistProxy('');
      this.busy = false;
      this.banner = removed
        ? '已移除无效代理设置。请在 ⚙ 中重新选择网络。'
        : '无效代理设置未能移除。请在 ⚙ 中重新选择网络。';
      return;
    }
    this.proxyInput = rule;
    this.changeProxy(rule, true);
  }

  private persistProxy(rule: string): boolean {
    const prefs = this.prefs;
    if (prefs === null) {
      return false;
    }
    try {
      if (rule.length > 0) {
        prefs.putSync(KEY_PROXY, rule);
      } else {
        prefs.deleteSync(KEY_PROXY);
      }
      prefs.flushSync();
      return true;
    } catch (_error) {
      return false;
    }
  }

  private canNavigate(): boolean {
    return this.webReady && !this.startupPaused && !this.proxyPending;
  }

  private stopLoading(): void {
    this.loadAttempt++;
    this.busy = false;
    if (this.webReady) {
      try {
        this.controller.stop();
      } catch (_error) {
        // An inactive Web instance must not prevent proxy configuration.
      }
    }
  }

  private changeProxy(target: string, fromSaved: boolean): void {
    if (!this.webReady || this.proxyPending) {
      return;
    }
    if (target === this.proxyActive) {
      this.startupPaused = false;
      this.proxyInput = target;
      const saved = this.persistProxy(target);
      this.loadHome();
      if (!saved) {
        this.banner = '本次网络设置已就绪，但未能保存。';
      }
      return;
    }

    this.proxyPending = true;
    this.stopLoading();
    this.banner = target.length > 0 ? '正在应用代理…' : '正在关闭代理…';
    let timedOut: boolean = false;
    let settled: boolean = false;
    let removedSavedRule: boolean = false;
    const watchdog: number = setTimeout(() => {
      if (settled) {
        return;
      }
      timedOut = true;
      // A timeout does not cancel ArkWeb's request. Keep navigation and the next operation blocked.
      if (fromSaved) {
        removedSavedRule = this.persistProxy('');
      }
      this.banner = '代理操作等待系统回调超时。请等待回调，或退出并重新打开应用。';
      if (fromSaved && !removedSavedRule) {
        this.banner += ' 未能清除旧设置。';
      }
    }, LOAD_TIMEOUT_MS);

    const finish = (success: boolean): void => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(watchdog);
      this.proxyPending = false;
      if (!success) {
        if (fromSaved) {
          this.proxyInput = '';
          removedSavedRule = this.persistProxy('');
        }
        if (fromSaved) {
          this.startupPaused = true;
        }
        this.banner = target.length > 0 ? '应用代理失败。' : '关闭代理失败，仍保留上次确认的设置。';
        if (fromSaved) {
          this.banner += removedSavedRule ? ' 已清除旧设置，请在 ⚙ 中重新选择网络。'
            : ' 未能清除旧设置，请在 ⚙ 中重新选择网络。';
        }
        return;
      }

      this.proxyActive = target;
      this.proxyInput = target;
      if (fromSaved && timedOut) {
        // Do not silently resume navigation or save an entry that timed out on startup.
        this.banner = '系统已返回代理状态。请在 ⚙ 中确认使用该代理或关闭代理。';
        if (!removedSavedRule) {
          this.banner += ' 旧设置未能清除。';
        }
        return;
      }
      this.startupPaused = false;
      const saved = this.persistProxy(target);
      this.loadHome();
      if (!saved) {
        this.banner = '本次网络设置已生效，但未能保存。';
      }
    };

    try {
      if (target.length > 0) {
        const config = new webview.ProxyConfig();
        config.insertProxyRule(target);
        webview.ProxyController.applyProxyOverride(config, () => finish(true));
      } else {
        webview.ProxyController.removeProxyOverride(() => finish(true));
      }
    } catch (_error) {
      finish(false);
    }
  }

  private saveProxy(): void {
    if (!this.webReady || this.proxyPending) {
      return;
    }
    const rule = normalizeProxy(this.proxyInput);
    if (rule.length === 0) {
      this.banner = '代理地址格式不对，应为 主机名或 IP:端口。';
      return;
    }
    this.changeProxy(rule, false);
  }

  private clearProxy(): void {
    this.changeProxy('', false);
  }

  private loadHome(): void {
    if (!this.canNavigate()) {
      return;
    }
    const attempt = ++this.loadAttempt;
    try {
      this.busy = true;
      this.controller.loadUrl(HOME_URL);
      setTimeout(() => {
        if (this.loadAttempt === attempt && this.busy && this.canNavigate()) {
          this.stopLoading();
          this.banner = '页面仍在加载，请检查网络或代理后点 ↻ 重试。';
        }
      }, LOAD_TIMEOUT_MS);
    } catch (_error) {
      this.loadAttempt++;
      this.busy = false;
      this.banner = '页面尚未就绪，请点 ↻ 重试。';
    }
  }

  private retry(): void {
    if (this.canNavigate()) {
      this.banner = '';
      this.loadHome();
    }
  }

  private goBack(): boolean {
    if (this.canNavigate()) {
      try {
        if (this.controller.accessBackward()) {
          this.controller.backward();
          return true;
        }
      } catch (_error) {
        // The web controller may have detached; the app can still go back.
      }
    }
    if (Number(router.getLength()) > 1) {
      router.back();
      return true;
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
        Button('保存并应用').enabled(this.webReady && !this.proxyPending).onClick(() => { this.saveProxy(); }).layoutWeight(1)
        Button('关闭代理').enabled(this.webReady && !this.proxyPending).onClick(() => { this.clearProxy(); }).layoutWeight(1)
      }.width('100%')
      if (!this.proxyPending && this.proxyActive.length > 0) {
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
        if (Number(router.getLength()) > 1) {
          Button('本地首页', { type: ButtonType.Normal }).fontSize(12).height(44)
            .accessibilityText('返回本地模拟时间线').onClick(() => { router.back(); })
        }
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
          if (this.canNavigate()) {
            Button('关闭').onClick(() => { this.banner = ''; })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 4 })
      }

      Web({ src: 'about:blank', controller: this.controller })
        .width('100%').layoutWeight(1)
        .javaScriptAccess(true).domStorageAccess(true).fileAccess(false)
        .mixedMode(MixedMode.None).multiWindowAccess(false)
        .onControllerAttached(() => {
          if (!this.webReady) {
            this.webReady = true;
            this.initializeNetwork();
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
          if (!this.canNavigate()) {
            return true;
          }
          if (!isAllowedNavigation(target)) {
            this.banner = '已拦截站外跳转';
            return true;
          }
          return false;
        })
        .onPageBegin((event) => {
          if (this.canNavigate() && event.url !== 'about:blank') {
            this.busy = true;
            this.banner = '';
          }
        })
        .onPageEnd((event) => {
          if (this.canNavigate() && event.url !== 'about:blank') {
            this.loadAttempt++;
            this.busy = false;
          }
        })
        .onErrorReceive((event) => {
          if (this.canNavigate() && event.request.isMainFrame()) {
            this.loadAttempt++;
            this.busy = false;
            this.banner = this.proxyActive.length > 0
              ? '页面加载失败：检查代理连接后点 ↻ 重试'
              : '页面加载失败：可检查网络或在 ⚙ 中设置代理';
          }
        })
        .onHttpErrorReceive((event) => {
          if (this.canNavigate() && event.request.isMainFrame()) {
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
