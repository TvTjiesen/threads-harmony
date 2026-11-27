const PREVIEW_RATIO = 4 / 3;
const COMPACT_HEIGHT = 120;
const VIEWER_ZOOM = 2;
const LOAD_ERROR = '照片无法加载';

// The caller must resolve and verify the app-private file before passing its URI here.
function isFileUri(uri: string): boolean {
  return uri.startsWith('file://') && uri.length > 'file://'.length;
}

@Component
export struct PostPhoto {
  @Prop @Watch('resetPhoto') uri: string = '';
  @Prop compact: boolean = false;
  onOpen?: () => void;
  @State private failed: boolean = false;
  @State private ratio: number = PREVIEW_RATIO;

  private resetPhoto(): void {
    this.failed = false;
    this.ratio = PREVIEW_RATIO;
  }

  private hasError(): boolean {
    return this.failed || !isFileUri(this.uri);
  }

  @Builder
  PreviewContent() {
    Stack() {
      if (!this.hasError()) {
        Image(this.uri).width('100%').height('100%').objectFit(ImageFit.Contain).autoResize(true)
          .accessibilityLevel('no')
          .onComplete((event) => {
            if (!this.compact && event && event.width > 0 && event.height > 0) {
              this.ratio = Math.max(0.8, Math.min(2.4, event.width / event.height));
            }
          })
          .onError(() => { this.failed = true; })
      } else {
        Text(LOAD_ERROR).id('post-photo-error').fontSize('14fp').textAlign(TextAlign.Center)
          .fontColor($r('app.color.timeline_text_primary')).padding(8).accessibilityLevel('no')
      }
    }.width('100%').height('100%')
  }

  build() {
    Stack() {
      if (this.onOpen !== undefined) {
        Button({ type: ButtonType.Normal }) {
          this.PreviewContent()
        }.id('post-photo').width('100%').height('100%').padding(0)
          .backgroundColor(Color.Transparent).accessibilityGroup(true)
          .accessibilityText(this.hasError() ? '照片无法加载，仍可打开预览' : '查看帖子照片')
          .onClick(() => { this.onOpen?.(); })
      } else {
        Stack() {
          this.PreviewContent()
        }.id('post-photo-draft').width('100%').height('100%').accessibilityLevel('yes')
          .accessibilityGroup(true).accessibilityText(this.hasError() ? LOAD_ERROR : '帖子照片附件')
      }
    }.width('100%').aspectRatio(this.compact ? 0 : this.ratio)
      .constraintSize({ minHeight: this.compact ? COMPACT_HEIGHT : 96, maxHeight: this.compact ? COMPACT_HEIGHT : 320 })
      .borderRadius(12).clip(true).backgroundColor($r('app.color.timeline_surface_muted'))
  }
}

@Component
export struct PhotoViewer {
  @Prop @Watch('resetViewer') uri: string = '';
  onClose: () => void = (): void => {};
  @State private failed: boolean = false;
  @State private ready: boolean = false;
  @State private zoom: number = 1;
  @State private frameWidth: number = 0;
  @State private frameHeight: number = 0;

  private resetViewer(): void {
    this.failed = false;
    this.ready = false;
    this.zoom = 1;
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button('返回', { type: ButtonType.Capsule }).id('photo-viewer-close')
          .constraintSize({ minWidth: 48, minHeight: 48 }).fontSize('16fp')
          .fontColor($r('app.color.timeline_text_primary')).backgroundColor($r('app.color.timeline_toolbar_button'))
          .accessibilityText('返回，关闭照片预览').onClick(() => this.onClose())
        Text('照片').layoutWeight(1).fontSize('18fp').fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.timeline_text_primary'))
        Button(this.zoom > 1 ? '适应屏幕' : '放大', { type: ButtonType.Capsule }).id('photo-viewer-zoom')
          .constraintSize({ minWidth: 48, minHeight: 48 }).fontSize('16fp').enabled(this.ready && !this.failed)
          .fontColor($r('app.color.timeline_text_primary')).backgroundColor($r('app.color.timeline_toolbar_button'))
          .accessibilityText(this.zoom > 1 ? '缩小照片至适应屏幕' : '放大照片，可滚动查看')
          .onClick(() => { this.zoom = this.zoom > 1 ? 1 : VIEWER_ZOOM; })
      }.width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
      Stack() {
        if (this.failed || !isFileUri(this.uri)) {
          Text(LOAD_ERROR).id('photo-viewer-error').fontSize('16fp').textAlign(TextAlign.Center)
            .fontColor($r('app.color.timeline_text_primary')).padding(16)
        } else if (this.frameWidth > 0 && this.frameHeight > 0) {
          Scroll() {
            Image(this.uri).width(this.frameWidth).height(this.frameHeight).objectFit(ImageFit.Contain)
              .accessibilityText('帖子照片').accessibilityLevel('yes')
              .onComplete((event) => { if (event && event.loadingStatus === 1) { this.ready = true; } })
              .onError(() => { this.failed = true; this.ready = false; })
          }.width('100%').height('100%').scrollable(ScrollDirection.FREE)
            .minZoomScale(1).maxZoomScale(VIEWER_ZOOM).zoomScale(this.zoom!!).enableBouncesZoom(false)
            .edgeEffect(EdgeEffect.None).clip(true)
        }
      }.width('100%').layoutWeight(1).backgroundColor($r('app.color.timeline_surface_muted'))
        .onAreaChange((_oldArea: Area, area: Area) => {
          const width = Number(area.width);
          const height = Number(area.height);
          if (width > 0 && width !== this.frameWidth) { this.frameWidth = width; }
          if (height > 0 && height !== this.frameHeight) { this.frameHeight = height; }
        })
    }.id('photo-viewer').width('100%').height('100%').backgroundColor($r('app.color.timeline_background'))
  }
}
