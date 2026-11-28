const PREVIEW_RATIO = 4 / 3;
const COMPACT_HEIGHT = 120;
const VIEWER_ZOOM = 2;
const PAGE_DURATION = 250;
const LOAD_ERROR = '照片无法加载';
const LOADING_PHOTO = '正在载入照片…';

// The caller must resolve and verify the app-private file before passing its URI here.
function isFileUri(uri: string): boolean {
  return uri.startsWith('file://') && uri.length > 'file://'.length;
}

function photoPosition(index: number, count: number): string {
  return '第 ' + (index + 1) + ' 张，共 ' + count + ' 张照片';
}

function photoIndex(index: number, count: number): number {
  return Number.isInteger(index) && index >= 0 && index < count ? index : 0;
}

function inPhotoWindow(index: number, current: number): boolean {
  return Math.abs(index - current) <= 1;
}

@Component
export struct PostPhoto {
  @Prop @Watch('resetPhoto') uri: string = '';
  @Prop compact: boolean = false;
  @Prop compactHeight: number = COMPACT_HEIGHT;
  @Prop elementId: string = '';
  @Prop galleryPosition: string = '';
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

  private openLabel(): string {
    const action = this.hasError() ? LOAD_ERROR + '，仍可打开预览' : '查看帖子照片';
    return this.galleryPosition === '' ? action : this.galleryPosition + '，' + action;
  }

  @Builder
  PreviewContent() {
    Stack() {
      if (!this.hasError()) {
        Image(this.uri).width('100%').height('100%').objectFit(ImageFit.Contain).autoResize(true)
          .accessibilityLevel('no')
          .onComplete((event) => {
            if (!this.compact && this.galleryPosition === '' && event && event.width > 0 && event.height > 0) {
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
        }.id(this.elementId || 'post-photo').width('100%').height('100%').padding(0)
          .backgroundColor(Color.Transparent).accessibilityGroup(true).accessibilityText(this.openLabel())
          .onClick(() => { this.onOpen?.(); })
      } else {
        Stack() {
          this.PreviewContent()
        }.id(this.elementId || 'post-photo-draft').width('100%').height('100%').accessibilityLevel('yes')
          .accessibilityGroup(true).accessibilityText(this.hasError() ? LOAD_ERROR : '帖子照片附件')
      }
    }.width('100%').aspectRatio(this.compact ? 0 : this.galleryPosition === '' ? this.ratio : PREVIEW_RATIO)
      .constraintSize({ minHeight: this.compact ? this.compactHeight : 96,
        maxHeight: this.compact ? this.compactHeight : 320 })
      .borderRadius(12).clip(true).backgroundColor($r('app.color.timeline_surface_muted'))
  }
}

@Component
struct PhotoPager {
  @Prop prefix: string = '';
  @Prop index: number = 0;
  @Prop count: number = 0;
  onPage: (index: number) => void = (_index: number): void => {};

  build() {
    Row({ space: 8 }) {
      Button('上一张', { type: ButtonType.Capsule }).id(this.prefix + '-prev')
        .constraintSize({ minWidth: 48, minHeight: 48 }).fontSize('14fp').enabled(this.index > 0)
        .fontColor($r('app.color.timeline_text_primary')).backgroundColor($r('app.color.timeline_toolbar_button'))
        .accessibilityText('上一张照片').onClick(() => { this.onPage(this.index - 1); })
      Text((this.index + 1) + ' / ' + this.count).id(this.prefix + '-position').layoutWeight(1)
        .fontSize('14fp').fontColor($r('app.color.timeline_text_secondary')).textAlign(TextAlign.Center)
        .accessibilityText(photoPosition(this.index, this.count)).accessibilityLevel('yes')
      Button('下一张', { type: ButtonType.Capsule }).id(this.prefix + '-next')
        .constraintSize({ minWidth: 48, minHeight: 48 }).fontSize('14fp').enabled(this.index < this.count - 1)
        .fontColor($r('app.color.timeline_text_primary')).backgroundColor($r('app.color.timeline_toolbar_button'))
        .accessibilityText('下一张照片').onClick(() => { this.onPage(this.index + 1); })
    }.width('100%')
  }
}

@Component
export struct PostGallery {
  @Prop @Watch('clampPosition') uris: string[] = [];
  @Prop motionEnabled: boolean = true;
  onOpen: (index: number) => void = (_index: number): void => {};
  @State private index: number = 0;
  private pager: SwiperController = new SwiperController();

  private clampPosition(): void {
    this.index = photoIndex(this.index, this.uris.length);
  }

  private goTo(index: number): void {
    if (index >= 0 && index < this.uris.length) {
      this.pager.changeIndex(index, this.motionEnabled);
    }
  }

  build() {
    Column({ space: 4 }) {
      if (this.uris.length === 1) {
        PostPhoto({ uri: this.uris[0], onOpen: () => this.onOpen(0) })
      } else if (this.uris.length > 1) {
        Swiper(this.pager) {
          ForEach(this.uris, (uri: string, index: number) => {
            Stack() {
              if (inPhotoWindow(index, this.index)) {
                PostPhoto({ uri: uri, elementId: 'post-photo-' + (index + 1),
                  galleryPosition: photoPosition(index, this.uris.length), onOpen: () => this.onOpen(index) })
              }
            }.width('100%').height('100%')
          }, (uri: string, index: number) => index + ':' + uri)
        }.id('post-gallery').width('100%').aspectRatio(PREVIEW_RATIO).constraintSize({ minHeight: 96, maxHeight: 320 })
          .vertical(false).index(this.index).indicator(false).autoPlay(false).loop(false).effectMode(EdgeEffect.None)
          .curve(Curve.EaseOut).duration(this.motionEnabled ? PAGE_DURATION : 0)
          .onChange((index: number) => { this.index = index; })
        PhotoPager({ prefix: 'post-gallery', index: this.index, count: this.uris.length,
          onPage: (index: number) => this.goTo(index) })
      }
    }.width('100%')
  }
}

@Component
struct ViewerPhotoPage {
  @Prop uri: string = '';
  @Prop label: string = '';
  @Prop active: boolean = true;
  @Prop zoomed: boolean = false;
  @Prop frameWidth: number = 0;
  @Prop frameHeight: number = 0;
  onReadyChange: (ready: boolean) => void = (_ready: boolean): void => {};
  @State private failed: boolean = false;
  @State private loaded: boolean = false;
  private mounted: boolean = false;

  aboutToAppear(): void {
    this.mounted = true;
  }

  aboutToDisappear(): void {
    this.mounted = false;
  }

  @Builder
  PhotoImage() {
    Image(this.uri)
      .width(this.frameWidth).height(this.frameHeight).objectFit(ImageFit.Contain)
      .accessibilityText(this.label).accessibilityLevel(this.active && this.loaded ? 'yes' : 'no')
      .onComplete((event) => {
        if (this.mounted && !this.failed && !this.loaded && event && event.loadingStatus === 1) {
          this.loaded = true;
          this.onReadyChange(true);
        }
      })
      .onError(() => {
        if (this.mounted && !this.failed) {
          this.failed = true;
          this.onReadyChange(false);
        }
      })
  }

  build() {
    Stack() {
      if (this.failed || !isFileUri(this.uri)) {
        Text(LOAD_ERROR).id(this.active ? 'photo-viewer-error' : '').fontSize('16fp').textAlign(TextAlign.Center)
          .fontColor($r('app.color.timeline_text_primary')).padding(16)
          .accessibilityText(this.label + '，' + LOAD_ERROR).accessibilityLevel(this.active ? 'yes' : 'no')
      } else if (this.frameWidth > 0 && this.frameHeight > 0) {
        if (this.zoomed) {
          Scroll() {
            this.PhotoImage()
          }.id('photo-viewer-pan').width('100%').height('100%').scrollable(ScrollDirection.FREE)
            .minZoomScale(VIEWER_ZOOM).maxZoomScale(VIEWER_ZOOM).zoomScale(VIEWER_ZOOM).enableBouncesZoom(false)
            .edgeEffect(EdgeEffect.None).clip(true)
        } else {
          this.PhotoImage()
        }
        if (this.active && !this.loaded) {
          Text(LOADING_PHOTO).id('photo-viewer-loading').fontSize('14fp').textAlign(TextAlign.Center)
            .fontColor($r('app.color.timeline_text_secondary')).padding(16).hitTestBehavior(HitTestMode.None)
            .accessibilityLevel('yes')
        }
      }
    }.width('100%').height('100%')
  }
}

@Component
export struct PhotoViewer {
  @Prop @Watch('resetGallery') uris: string[] = [];
  @Prop @Watch('resetInitialIndex') initialIndex: number = 0;
  @Prop motionEnabled: boolean = true;
  onClose: () => void = (): void => {};
  @State private index: number = 0;
  @State private zoomed: boolean = false;
  @State private ready: boolean[] = [];
  @State private frameWidth: number = 0;
  @State private frameHeight: number = 0;
  private lastUris: string[] = [];
  private pager: SwiperController = new SwiperController();

  aboutToAppear(): void {
    this.resetGallery();
  }

  private resetGallery(): void {
    if (this.uris.length !== this.lastUris.length || this.uris.some((uri: string, index: number) =>
      uri !== this.lastUris[index])) {
      this.ready = this.ready.slice(0, this.uris.length).map((ready: boolean, index: number) =>
        ready && this.uris[index] === this.lastUris[index]);
      this.lastUris = this.uris.slice();
      this.resetInitialIndex();
    }
  }

  private resetInitialIndex(): void {
    this.selectPhoto(photoIndex(this.initialIndex, this.uris.length));
  }

  private pageChanged(index: number): void {
    if (this.index !== index) {
      this.selectPhoto(photoIndex(index, this.uris.length));
    }
  }

  private selectPhoto(index: number): void {
    this.zoomed = false;
    this.index = index;
    if (this.ready.some((ready: boolean, page: number) => ready && !inPhotoWindow(page, index))) {
      this.ready = this.ready.map((ready: boolean, page: number) => ready && inPhotoWindow(page, index));
    }
  }

  private goTo(index: number): void {
    if (index >= 0 && index < this.uris.length && index !== this.index) {
      this.zoomed = false;
      this.pager.changeIndex(index, this.motionEnabled);
    }
  }

  private setPhotoReady(uri: string, index: number, ready: boolean): void {
    if (this.uris[index] === uri && inPhotoWindow(index, this.index) && (this.ready[index] === true) !== ready) {
      const next = this.ready.slice();
      next[index] = ready;
      this.ready = next;
      if (index === this.index && !ready) { this.zoomed = false; }
    }
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
        Button(this.zoomed ? '适应屏幕' : '放大', { type: ButtonType.Capsule }).id('photo-viewer-zoom')
          .constraintSize({ minWidth: 48, minHeight: 48 }).fontSize('16fp').enabled(this.ready[this.index] === true)
          .fontColor($r('app.color.timeline_text_primary')).backgroundColor($r('app.color.timeline_toolbar_button'))
          .accessibilityText(this.zoomed ? '缩小照片至适应屏幕' : '放大照片，可滚动查看')
          .onClick(() => { this.zoomed = !this.zoomed; })
      }.width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
      Stack() {
        if (this.uris.length > 0) {
          Swiper(this.pager) {
            ForEach(this.uris, (uri: string, index: number) => {
              Stack() {
                if (inPhotoWindow(index, this.index)) {
                  ViewerPhotoPage({ uri: uri, label: this.uris.length === 1 ? '帖子照片' : photoPosition(index, this.uris.length),
                    active: index === this.index, zoomed: index === this.index && this.zoomed,
                    frameWidth: this.frameWidth, frameHeight: this.frameHeight,
                    onReadyChange: (ready: boolean) => this.setPhotoReady(uri, index, ready) })
                }
              }.width('100%').height('100%')
            }, (uri: string, index: number) => index + ':' + uri)
          }.id('photo-viewer-swiper').width('100%').height('100%').vertical(false).index(this.index)
            .indicator(false).autoPlay(false).loop(false).effectMode(EdgeEffect.None)
            // At fit there is no inner Scroll recognizer; at zoom only the photo pans.
            .disableSwipe(this.zoomed || this.uris.length < 2)
            .curve(Curve.EaseOut).duration(this.motionEnabled ? PAGE_DURATION : 0)
            .onChange((index: number) => this.pageChanged(index))
        } else {
          Text(LOAD_ERROR).id('photo-viewer-error').fontSize('16fp').textAlign(TextAlign.Center)
            .fontColor($r('app.color.timeline_text_primary')).padding(16)
        }
      }.width('100%').layoutWeight(1).backgroundColor($r('app.color.timeline_surface_muted'))
        .onAreaChange((_oldArea: Area, area: Area) => {
          const width = Number(area.width);
          const height = Number(area.height);
          if (width > 0 && width !== this.frameWidth) { this.frameWidth = width; }
          if (height > 0 && height !== this.frameHeight) { this.frameHeight = height; }
        })
      if (this.uris.length > 1) {
        Column() {
          PhotoPager({ prefix: 'photo-viewer', index: this.index, count: this.uris.length,
            onPage: (index: number) => this.goTo(index) })
        }.width('100%').padding({ left: 12, right: 12, top: 4, bottom: 4 })
      }
    }.id('photo-viewer').width('100%').height('100%').backgroundColor($r('app.color.timeline_background'))
  }
}
