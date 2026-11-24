import { url } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';

function isAllowedMainFrame(requestUrl: string): boolean {
  let parsed: url.URL;
  try {
    parsed = new url.URL(requestUrl);
  } catch (error) {
    return false;
  }

  const protocol = parsed.protocol.endsWith(':') ? parsed.protocol.slice(0, -1) : parsed.protocol;
  if (protocol !== 'https') {
    return false;
  }
  if (parsed.username.length > 0 || parsed.password.length > 0) {
    return false;
  }
  if (parsed.port.length > 0 && parsed.port !== '443') {
    return false;
  }

  const host = parsed.hostname.toLowerCase();
  return host === 'threads.com' || host === 'www.threads.com' ||
    host === 'threads.net' || host === 'www.threads.net';
}

@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  @State isLoading: boolean = true;
  @State loadError: boolean = false;

  build() {
    Column() {
      Row() {
        Button('返回')
          .fontSize(14)
          .onClick(() => {
            if (this.controller.accessBackward()) {
              this.controller.backward();
            }
          })

        Text('Threads')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Button('刷新')
          .fontSize(14)
          .onClick(() => {
            this.loadError = false;
            this.isLoading = true;
            this.controller.refresh();
          })
      }
      .width('100%')
      .height(48)
      .padding({ left: 12, right: 12 })

      if (this.isLoading) {
        Row() {
          LoadingProgress()
            .width(20)
            .height(20)

          Text('加载中...')
            .fontSize(14)
            .margin({ left: 8 })
        }
        .height(32)
      }

      if (this.loadError) {
        Text('主页面加载失败')
          .fontSize(16)
          .fontColor(Color.Red)
          .margin({ top: 8, bottom: 8 })
      }

      Web({ src: 'https://www.threads.com/', controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onlineImageAccess(true)
        .fileAccess(false)
        .mixedMode(MixedMode.None)
        .multiWindowAccess(false)
        .onPageBegin(() => {
          this.isLoading = true;
          this.loadError = false;
        })
        .onPageEnd(() => {
          this.isLoading = false;
        })
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          if (event.request.isMainFrame()) {
            this.isLoading = false;
            this.loadError = true;
          }
        })
        .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
          if (event.request.isMainFrame()) {
            this.isLoading = false;
            this.loadError = true;
          }
        })
        .onPermissionRequest((event: OnPermissionRequestEvent) => {
          event.request.deny();
        })
        .onSslErrorEventReceive((event: OnSslErrorEventReceiveEvent) => {
          event.handler.handleCancel();
        })
        .onLoadIntercept((event: OnLoadInterceptEvent): boolean => {
          if (!event.data.isMainFrame()) {
            return false;
          }
          return !isAllowedMainFrame(event.data.getRequestUrl());
        })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}