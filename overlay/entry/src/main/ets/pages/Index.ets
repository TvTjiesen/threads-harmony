import { webview } from '@kit.ArkWeb';
import { url } from '@kit.ArkTS';

const HOME_URL: string = 'https://www.threads.com/';
const TOP_LEVEL_HOSTS: string[] = [
  'www.threads.com', 'threads.com', 'www.threads.net', 'threads.net',
  'www.instagram.com', 'instagram.com', 'accountscenter.facebook.com',
  'www.facebook.com', 'facebook.com', 'm.facebook.com', 'auth.meta.com'
];

function isAllowedNavigation(target: string): boolean {
  try {
    const parsed = url.URL.parseURL(target);
    return parsed.protocol === 'https:' && parsed.username === '' && parsed.password === '' &&
      (parsed.port === '' || parsed.port === '443') && TOP_LEVEL_HOSTS.includes(parsed.hostname);
  } catch (_error) {
    return false;
  }
}

@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  @State private busy: boolean = true;
  @State private banner: string = '';

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
    return this.goBack();
  }

  private retry(): void {
    try {
      this.banner = '';
      this.controller.refresh();
    } catch (_error) {
      this.banner = '页面还未就绪';
    }
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
        Button('↻', { type: ButtonType.Normal })
          .fontSize(20)
          .width(48)
          .height(48)
          .accessibilityText('重新加载')
          .onClick(() => { this.retry(); })
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })

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
        .onPageBegin(() => { this.busy = true; })
        .onPageEnd(() => { this.busy = false; })
        .onErrorReceive((event) => {
          if (event?.request.isMainFrame()) {
            this.busy = false;
            this.banner = '页面加载失败，可尝试重新加载';
          }
        })
    }
    .width('100%')
    .height('100%')
  }
}
