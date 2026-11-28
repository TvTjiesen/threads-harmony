import { webview } from '@kit.ArkWeb';
import { url } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

const HOME_URL: string = 'https://www.threads.com/';
const TOP_LEVEL_HOSTS: string[] = [
  'www.threads.com', 'threads.com', 'www.threads.net', 'threads.net',
  'www.instagram.com', 'instagram.com', 'accountscenter.facebook.com',
  'www.facebook.com', 'facebook.com', 'm.facebook.com', 'auth.meta.com'
];
const PREF_NAME: string = 'threads_settings';
const KEY_PROXY: string = 'proxy';
const LOAD_TIMEOUT_MS: number = 20000;

// ArkWeb overrides are shared by all Web components in this app, even across page instances.
class AppProxyState {
  pending: boolean = false;
  active: string = '';
  hasApplied: boolean = false;
  requiresConfirmation: boolean = false;
  onSettled: (() => void) | undefined = undefined;
}
const appProxy = new AppProxyState();

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
  private loadWatchdog: number | undefined = undefined;
  @State private browserFallback: boolean = false;
  private startupPaused: boolean = true;
  @State private proxyPending: boolean = false;
  @State private externalHomeFailed: boolean = false;
  private proxyWaiter: (() => void) | undefined = undefined;

  private initializeNetwork(): void {
    if (appProxy.pending) {
      this.proxyPending = true;
      this.failLoading('上一项代理操作仍在等待系统。可返回或用系统浏览器对照。');
      this.proxyWaiter = () => {
        this.proxyWaiter = undefined;
        this.proxyPending = false;
        if (this.webReady) {
          this.initializeNetwork();
        }
      };
      appProxy.onSettled = this.proxyWaiter;
      return;
    }
    this.proxyActive = appProxy.active;
    this.proxyInput = appProxy.active;
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
    if (appProxy.requiresConfirmation) {
      this.failLoading('系统已返回代理状态。请在 ⚙ 中确认使用该代理或关闭代理。');
      return;
    }
    if (appProxy.hasApplied || saved === '') {
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
    return this.webReady && !this.startupPaused && !this.proxyPending && !appProxy.pending;
  }

  private finishLoading(): void {
    this.loadAttempt++;
    if (this.loadWatchdog !== undefined) {
      clearTimeout(this.loadWatchdog);
      this.loadWatchdog = undefined;
    }
    this.busy = false;
  }

  private stopLoading(): void {
    this.finishLoading();
    if (this.webReady) {
      try {
        this.controller.stop();
      } catch (_error) {
        // An inactive Web instance must not prevent proxy configuration.
      }
    }
  }

  private changeProxy(target: string, fromSaved: boolean): void {
    if (!this.webReady || this.proxyPending || appProxy.pending) {
      return;
    }
    if (target === appProxy.active) {
      appProxy.requiresConfirmation = false;
      appProxy.hasApplied = true;
      this.startupPaused = false;
      this.proxyInput = target;
      const saved = this.persistProxy(target);
      this.loadHome();
      if (!saved) {
        this.banner = '本次网络设置已就绪，但未能保存。';
      }
      return;
    }

    appProxy.pending = true;
    this.proxyPending = true;
    this.stopLoading();
    this.browserFallback = false;
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
      if (this.webReady) {
        this.failLoading('代理操作等待系统回调超时。可用系统浏览器对照，或结束应用进程后重开。' +
          (fromSaved && !removedSavedRule ? ' 未能清除旧设置。' : ''));
      }
    }, LOAD_TIMEOUT_MS);

    const finish = (success: boolean): void => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(watchdog);
      appProxy.pending = false;
      const waiter = appProxy.onSettled;
      appProxy.onSettled = undefined;
      if (this.webReady) { this.proxyPending = false; }
      try {
        if (!success) {
          if (fromSaved) {
            removedSavedRule = this.persistProxy('');
          }
          if (this.webReady) {
            if (fromSaved) {
              this.proxyInput = '';
              this.startupPaused = true;
            }
            let message = target.length > 0 ? '应用代理失败。' : '关闭代理失败，仍保留上次确认的设置。';
            if (fromSaved) {
              message += removedSavedRule ? ' 已清除旧设置，请在 ⚙ 中重新选择网络。'
                : ' 未能清除旧设置，请在 ⚙ 中重新选择网络。';
            }
            this.failLoading(message);
          }
          return;
        }

        appProxy.active = target;
        appProxy.hasApplied = true;
        appProxy.requiresConfirmation = fromSaved && timedOut;
        if (this.webReady) {
          this.proxyActive = target;
          this.proxyInput = target;
        }
        if (fromSaved && timedOut) {
          // Keep the confirmation gate across page reentry as well.
          if (this.webReady) {
            this.failLoading('系统已返回代理状态。请在 ⚙ 中确认使用该代理或关闭代理。' +
              (!removedSavedRule ? ' 旧设置未能清除。' : ''));
          }
          return;
        }
        const saved = this.persistProxy(target);
        if (this.webReady) {
          this.startupPaused = false;
          this.loadHome();
          if (!saved) {
            this.banner = '本次网络设置已生效，但未能保存。';
          }
        }
      } finally {
        if (waiter !== undefined) { waiter(); }
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

  private beginLoading(): void {
    this.finishLoading();
    const attempt = this.loadAttempt;
    this.busy = true;
    this.banner = '';
    this.browserFallback = false;
    this.externalHomeFailed = false;
    this.loadWatchdog = setTimeout(() => {
      if (this.loadAttempt === attempt && this.busy && this.canNavigate()) {
        this.failLoading('Threads 网页加载超时。可重试，或用系统浏览器对照。');
        this.stopLoading();
      }
    }, LOAD_TIMEOUT_MS);
  }

  private failLoading(message: string): void {
    this.finishLoading();
    this.banner = message;
    this.browserFallback = true;
  }

  private loadHome(): void {
    if (!this.canNavigate()) {
      return;
    }
    this.beginLoading();
    try {
      this.controller.loadUrl(HOME_URL);
    } catch (_error) {
      this.failLoading('应用内网页尚未就绪，可重试或用系统浏览器打开。');
    }
  }

  private retry(): void {
    this.loadHome();
  }

  aboutToDisappear(): void {
    this.webReady = false;
    if (this.proxyWaiter !== undefined && appProxy.onSettled === this.proxyWaiter) {
      appProxy.onSettled = undefined;
    }
    this.proxyWaiter = undefined;
    this.finishLoading();
  }

  private async openExternalHome(): Promise<void> {
    this.externalHomeFailed = false;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (!context) {
        this.externalHomeFailed = true;
        return;
      }
      await context.openLink(HOME_URL, { appLinkingOnly: false });
    } catch (_error) {
      this.externalHomeFailed = true;
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
  WebAction(icon: Resource, label: string, controlId: string, action: () => void) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(icon).fontSize('21vp').fontColor([$r('app.color.timeline_text_primary')])
    }
    .id(controlId).width(48).height(48).padding(0).buttonStyle(ButtonStyleMode.TEXTUAL)
    .focusable(true).accessibilityText(label).onClick(action)
  }

  @Builder
  WebToolbar() {
    Row() {
      this.WebAction($r('sys.symbol.chevron_left'), '返回上一页', 'web-back', () => { this.goBack(); })
      Text('Threads').fontSize(20).fontWeight(FontWeight.Medium).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        .fontColor($r('app.color.timeline_text_primary')).margin({ left: 4, right: 4 })
      if (Number(router.getLength()) > 1) {
        this.WebAction($r('sys.symbol.house'), '返回本地首页', 'web-local-home', () => { router.back(); })
      }
      this.WebAction($r('sys.symbol.gearshape'), '网络设置', 'web-settings', () => { this.showSettings = true; })
      this.WebAction($r('sys.symbol.arrow_clockwise'), '重新加载官网首页', 'web-reload', () => { this.retry(); })
    }
    .id('web-toolbar').width('100%').padding({ left: 8, right: 8, top: 4, bottom: 4 })
  }

  @Builder
  SettingsPanel() {
    Scroll() {
      Column({ space: 12 }) {
        Text('网络设置').fontSize(22).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.timeline_text_primary'))
        Text('代理仅作用于应用内网页。可填写已有代理的主机和端口，不含账号或密码。')
          .fontSize(14).fontColor($r('app.color.timeline_text_secondary'))
        TextInput({ text: this.proxyInput, placeholder: '主机:端口' })
          .id('web-proxy-input').accessibilityText('代理地址')
          .onChange((value: string) => { this.proxyInput = value; }).width('100%')
        if (this.proxyPending) {
          Text('正在等待系统应用网络设置').fontSize(14).fontColor($r('app.color.timeline_text_secondary'))
        } else if (this.proxyActive.length > 0) {
          Text('应用内代理已启用').fontSize(14).fontColor($r('app.color.timeline_text_secondary'))
        }
        if (this.banner.length > 0) {
          Text(this.banner).id('web-settings-notice').fontSize(14)
            .fontColor($r('app.color.timeline_text_body'))
        }
        Flex({ wrap: FlexWrap.Wrap }) {
          Button('保存并应用').id('web-proxy-save').constraintSize({ minHeight: 48, maxWidth: '100%' })
            .buttonStyle(ButtonStyleMode.TEXTUAL).enabled(this.webReady && !this.proxyPending)
            .onClick(() => { this.saveProxy(); })
          Button('关闭代理').id('web-proxy-clear').constraintSize({ minHeight: 48, maxWidth: '100%' })
            .buttonStyle(ButtonStyleMode.TEXTUAL).enabled(this.webReady && !this.proxyPending)
            .onClick(() => { this.clearProxy(); })
        }.width('100%')
        Divider().color($r('app.color.timeline_border'))
        Button('通过系统打开 Threads 网页').id('web-settings-browser')
          .constraintSize({ minHeight: 48, maxWidth: '100%' }).buttonStyle(ButtonStyleMode.TEXTUAL)
          .onClick(() => { this.openExternalHome(); })
        if (this.externalHomeFailed) {
          Text(`系统未能打开链接。请在浏览器中手动访问 ${HOME_URL}`).fontSize(14)
            .fontColor($r('app.color.timeline_text_body'))
        }
        Button('完成').id('web-settings-done').constraintSize({ minHeight: 48, maxWidth: '100%' })
          .buttonStyle(ButtonStyleMode.TEXTUAL).onClick(() => { this.showSettings = false; })
      }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 20, right: 20, top: 12, bottom: 20 })
    }.width('100%')
  }

  @Builder
  WebNotice() {
    Scroll() {
      Column({ space: 4 }) {
        Text(this.browserFallback ? '网页暂不可用' : '网页提示').fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.timeline_text_primary'))
        Text(this.banner).fontSize(14).fontColor($r('app.color.timeline_text_body')).width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          if (this.browserFallback) {
            if (this.canNavigate()) {
              Button('重试网页').id('web-failure-retry').constraintSize({ minHeight: 48, maxWidth: '100%' })
                .buttonStyle(ButtonStyleMode.TEXTUAL).onClick(() => { this.retry(); })
            }
            Button('用系统浏览器打开').id('web-failure-browser').constraintSize({ minHeight: 48, maxWidth: '100%' })
              .buttonStyle(ButtonStyleMode.TEXTUAL).onClick(() => { this.openExternalHome(); })
          } else if (this.canNavigate()) {
            Button('关闭').id('web-notice-dismiss').constraintSize({ minHeight: 48 })
              .buttonStyle(ButtonStyleMode.TEXTUAL).onClick(() => { this.banner = ''; })
          }
        }.width('100%')
        if (this.browserFallback && this.externalHomeFailed) {
          Text(`系统未能打开链接。请在浏览器中手动访问 ${HOME_URL}`).fontSize(14)
            .fontColor($r('app.color.timeline_text_body'))
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 10, bottom: 4 })
    }.id('web-notice').width('100%').constraintSize({ maxHeight: '38%' })
      .backgroundColor($r('app.color.timeline_surface_muted'))
  }

  build() {
    Column() {
      this.WebToolbar()
      Divider().color($r('app.color.timeline_border'))
      if (this.busy) {
        LoadingProgress().width(20).height(20).margin(4).accessibilityText('加载中')
      }
      if (this.banner.length > 0 && !this.showSettings) {
        this.WebNotice()
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
            if (!this.browserFallback) {
              this.failLoading('已拦截站外跳转。可重新加载 Threads，或在系统浏览器打开官网。');
            }
            return true;
          }
          return false;
        })
        .onPageBegin((event) => {
          if (this.canNavigate() && isAllowedNavigation(event.url) && !this.busy && !this.browserFallback) {
            this.beginLoading();
          }
        })
        .onPageEnd((event) => {
          if (this.canNavigate() && isAllowedNavigation(event.url) && this.busy) {
            this.finishLoading();
          }
        })
        .onErrorReceive((event) => {
          if (this.canNavigate() && event.request.isMainFrame() && !this.browserFallback) {
            this.failLoading(this.proxyActive.length > 0
              ? 'Threads 网页加载失败。可检查应用内代理，或用系统浏览器对照。'
              : 'Threads 网页加载失败。可重试，或用系统浏览器对照。');
          }
        })
        .onHttpErrorReceive((event) => {
          if (this.canNavigate() && event.request.isMainFrame() && !this.browserFallback) {
            this.failLoading(`网页响应异常（HTTP ${event.response.getResponseCode()}）。`);
          }
        })
        .onPermissionRequest((event) => { event.request.deny(); })
        .onSslErrorEventReceive((event) => {
          event.handler.handleCancel();
          if (this.canNavigate()) {
            this.failLoading('无法验证网页的安全连接。已停止加载，不会忽略证书错误。');
          }
        })
    }
    .width('100%').height('100%').backgroundColor($r('app.color.timeline_surface'))
    .bindSheet($$this.showSettings, this.SettingsPanel(), {
      height: SheetSize.LARGE,
      showClose: false,
      dragBar: true,
      backgroundColor: $r('app.color.timeline_surface')
    })
  }
}
