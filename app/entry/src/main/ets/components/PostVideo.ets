const COVER_RATIO = 16 / 9;
const COMPACT_HEIGHT = 120;
const SKIP_SECONDS = 5;
const PLAYBACK_ERROR = '无法播放此视频，可重试或返回。';
const MISSING_VIDEO = '本机视频文件不可用。';

function isLocalUri(uri: string): boolean {
  return uri.startsWith('file://') && uri.length > 'file://'.length;
}

function durationSeconds(ms: number): number {
  return Number.isFinite(ms) && ms > 0 ? ms / 1000 : 0;
}

function twoDigits(value: number): string {
  return value < 10 ? '0' + value : String(value);
}

function timestamp(seconds: number): string {
  const whole = Math.floor(seconds);
  const hours = Math.floor(whole / 3600);
  const minutes = Math.floor(whole / 60) % 60;
  const remainder = twoDigits(whole % 60);
  return (hours > 0 ? hours + ':' : '') + twoDigits(minutes) + ':' + remainder;
}

function spokenDuration(seconds: number): string {
  const whole = Math.floor(seconds);
  const hours = Math.floor(whole / 3600);
  const minutes = Math.floor(whole / 60) % 60;
  return (hours > 0 ? hours + ' 小时 ' : '') + (minutes > 0 ? minutes + ' 分 ' : '') + (whole % 60) + ' 秒';
}

@Component
export struct PostVideo {
  @Prop @Watch('resetPoster') posterUri: string = '';
  @Prop durationMs: number = 0;
  @Prop compact: boolean = false;
  onOpen?: () => void;
  @State private posterFailed: boolean = false;

  private resetPoster(): void {
    this.posterFailed = false;
  }

  private coverLabel(label: string): string {
    const seconds = durationSeconds(this.durationMs);
    return label + (seconds > 0 ? '，时长 ' + spokenDuration(seconds) : '，时长未知');
  }

  @Builder
  Cover() {
    Stack({ alignContent: Alignment.Center }) {
      if (!this.posterFailed && isLocalUri(this.posterUri)) {
        Image(this.posterUri).width('100%').height('100%').objectFit(ImageFit.Cover).autoResize(true)
          .accessibilityLevel('no').onError(() => { this.posterFailed = true; })
      }
      if (this.onOpen !== undefined) {
        Text('▶').width(48).height(48).textAlign(TextAlign.Center).fontSize(20)
          .fontColor(Color.White).backgroundColor('#C0000000').borderRadius(24).accessibilityLevel('no')
      } else {
        Text('视频').fontSize('14fp').fontColor(Color.White).backgroundColor('#C0000000')
          .padding({ left: 10, right: 10, top: 5, bottom: 5 }).borderRadius(8).accessibilityLevel('no')
      }
      Stack({ alignContent: Alignment.BottomEnd }) {
        Text(durationSeconds(this.durationMs) > 0 ? timestamp(durationSeconds(this.durationMs)) : '时长未知')
          .fontSize('12fp').fontWeight(FontWeight.Medium).fontColor(Color.White).backgroundColor('#C0000000')
          .padding({ left: 8, right: 8, top: 3, bottom: 3 }).borderRadius(8).accessibilityLevel('no')
      }.width('100%').height('100%').padding(8).hitTestBehavior(HitTestMode.None)
    }.width('100%').height('100%')
  }

  build() {
    Stack() {
      if (this.onOpen !== undefined) {
        Button({ type: ButtonType.Normal }) {
          this.Cover()
        }.id('post-video-open').width('100%').height('100%').padding(0).backgroundColor(Color.Transparent)
          .accessibilityGroup(true).accessibilityText(this.coverLabel('打开视频播放器'))
          .onClick(() => { this.onOpen?.(); })
      } else {
        Stack() {
          this.Cover()
        }.id('post-video-preview').width('100%').height('100%').accessibilityLevel('yes')
          .accessibilityGroup(true).accessibilityText(this.coverLabel('视频附件'))
      }
    }.width('100%').aspectRatio(this.compact ? 0 : COVER_RATIO)
      .constraintSize({ minHeight: this.compact ? COMPACT_HEIGHT : 96, maxHeight: this.compact ? COMPACT_HEIGHT : 300 })
      .borderRadius(12).clip(true).backgroundColor($r('app.color.timeline_surface_muted'))
  }
}

@Component
export struct PostVideoPlayer {
  @Prop uri: string = '';
  @Prop posterUri: string = '';
  @Prop durationMs: number = 0;
  @Prop @Watch('onActiveChange') active: boolean = false;
  onClose: () => void = (): void => {};
  @State private prepared: boolean = false;
  @State private failed: boolean = false;
  @State private wantsPlayback: boolean = false;
  @State private finished: boolean = false;
  @State private mediaDuration: number = 0;
  @State private playbackPosition: number = 0;
  @State private scrubbing: boolean = false;
  @State private scrubPosition: number = 0;
  private controller: VideoController = new VideoController();
  private mounted: boolean = false;

  aboutToAppear(): void {
    this.mounted = true;
  }

  aboutToDisappear(): void {
    this.stopForExit();
  }

  private onActiveChange(): void {
    if (!this.active) {
      this.wantsPlayback = false;
      this.scrubbing = false;
      this.controller.pause();
    }
  }

  private stopForExit(): void {
    if (this.mounted) {
      this.mounted = false;
      this.controller.stop();
    }
  }

  private totalSeconds(): number {
    return this.mediaDuration > 0 ? this.mediaDuration : durationSeconds(this.durationMs);
  }

  private visiblePosition(): number {
    return this.scrubbing ? this.scrubPosition : this.playbackPosition;
  }

  private canControl(): boolean {
    return this.active && this.mounted && this.prepared && !this.failed;
  }

  private seekTo(seconds: number): void {
    const total = this.totalSeconds();
    if (!this.canControl() || total <= 0 || !Number.isFinite(seconds)) { return; }
    const target = Math.max(0, Math.min(total, seconds));
    this.playbackPosition = target;
    this.finished = target >= total;
    this.controller.setCurrentTime(target, SeekMode.Accurate);
  }

  private sliderChanged(percent: number, mode: SliderChangeMode): void {
    if (!this.canControl()) { return; }
    const target = this.totalSeconds() * percent / 100;
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.scrubbing = true;
      this.scrubPosition = target;
    } else {
      this.scrubbing = false;
      this.seekTo(target);
    }
  }

  private togglePlayback(): void {
    if (!this.canControl()) { return; }
    if (this.wantsPlayback) {
      this.wantsPlayback = false;
      this.controller.pause();
      return;
    }
    if (this.finished) { this.seekTo(0); }
    this.wantsPlayback = true;
    this.controller.start();
  }

  private updatePosition(time: number): void {
    if (this.mounted && !this.failed && !this.scrubbing && !this.finished && Number.isFinite(time) && time >= 0) {
      const total = this.totalSeconds();
      this.playbackPosition = total > 0 ? Math.min(time, total) : time;
    }
  }

  private failPlayback(): void {
    if (!this.mounted || this.failed) { return; }
    this.failed = true;
    this.prepared = false;
    this.wantsPlayback = false;
    this.scrubbing = false;
    this.controller.pause();
  }

  private retryPlayback(): void {
    if (!this.active || !this.mounted || !this.failed) { return; }
    this.controller = new VideoController();
    this.playbackPosition = 0;
    this.mediaDuration = 0;
    this.finished = false;
    this.failed = false;
  }

  @Builder
  PlayerControls() {
    Column({ space: 6 }) {
      Slider({ value: this.totalSeconds() > 0 ? this.visiblePosition() * 100 / this.totalSeconds() : 0,
        min: 0, max: 100, step: 1 }).id('post-video-seek').width('100%').constraintSize({ minHeight: 44 })
        .enabled(this.canControl() && this.totalSeconds() > 0).accessibilityText('视频播放进度')
        .onChange((value: number, mode: SliderChangeMode) => this.sliderChanged(value, mode))
      Text(timestamp(this.visiblePosition()) + ' / ' + timestamp(this.totalSeconds())).id('post-video-time')
        .fontSize('13fp').fontColor($r('app.color.timeline_text_secondary'))
        .accessibilityText('当前 ' + spokenDuration(this.visiblePosition()) + '，总时长 ' + spokenDuration(this.totalSeconds()))
      Row({ space: 8 }) {
        Button('−5 秒', { type: ButtonType.Capsule }).id('post-video-rewind')
          .constraintSize({ minWidth: 48, minHeight: 48 }).fontSize('14fp')
          .fontColor($r('app.color.timeline_text_primary')).backgroundColor($r('app.color.timeline_toolbar_button'))
          .enabled(this.canControl() && this.totalSeconds() > 0 && this.playbackPosition > 0).accessibilityText('后退 5 秒')
          .onClick(() => { this.seekTo(this.playbackPosition - SKIP_SECONDS); })
        Button(this.wantsPlayback ? '暂停' : this.finished ? '重播' : '播放', { type: ButtonType.Capsule })
          .id('post-video-play-toggle').constraintSize({ minWidth: 64, minHeight: 48 }).fontSize('16fp')
          .fontColor($r('app.color.timeline_on_action')).backgroundColor($r('app.color.timeline_action'))
          .enabled(this.canControl()).accessibilityText(this.wantsPlayback ? '暂停视频' : this.finished ? '重播视频' : '播放视频')
          .onClick(() => { this.togglePlayback(); })
        Button('+5 秒', { type: ButtonType.Capsule }).id('post-video-forward')
          .constraintSize({ minWidth: 48, minHeight: 48 }).fontSize('14fp')
          .fontColor($r('app.color.timeline_text_primary')).backgroundColor($r('app.color.timeline_toolbar_button'))
          .enabled(this.canControl() && this.totalSeconds() > this.playbackPosition).accessibilityText('前进 5 秒')
          .onClick(() => { this.seekTo(this.playbackPosition + SKIP_SECONDS); })
      }.justifyContent(FlexAlign.Center).width('100%')
    }.width('100%').padding({ left: 12, right: 12, bottom: 12, top: 6 })
  }

  // Smoke IDs: post-video-open / post-video-preview; post-video-player, post-video-close,
  // post-video-surface, post-video-play-toggle, post-video-seek, post-video-rewind, post-video-forward,
  // post-video-time, post-video-error, post-video-retry.
  build() {
    Column() {
      Row({ space: 12 }) {
        Button('返回', { type: ButtonType.Capsule }).id('post-video-close')
          .constraintSize({ minWidth: 48, minHeight: 48 }).fontSize('16fp')
          .fontColor($r('app.color.timeline_text_primary')).backgroundColor($r('app.color.timeline_toolbar_button'))
          .accessibilityText('返回，关闭视频播放器').onClick(() => {
            this.stopForExit();
            this.onClose();
          })
        Text('视频').layoutWeight(1).fontSize('18fp').fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.timeline_text_primary'))
      }.width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
      if (this.failed || !isLocalUri(this.uri)) {
        Column({ space: 12 }) {
          Text(this.failed ? PLAYBACK_ERROR : MISSING_VIDEO).id('post-video-error').fontSize('16fp')
            .fontColor($r('app.color.timeline_text_primary')).textAlign(TextAlign.Center)
          if (this.failed) {
            Button('重试', { type: ButtonType.Capsule }).id('post-video-retry')
              .constraintSize({ minWidth: 48, minHeight: 48 }).fontSize('16fp').enabled(this.active)
              .fontColor($r('app.color.timeline_on_action')).backgroundColor($r('app.color.timeline_action'))
              .onClick(() => { this.retryPlayback(); })
          }
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding(16)
      } else {
        Stack() {
          Video({ src: this.uri, previewUri: isLocalUri(this.posterUri) ? this.posterUri : '', controller: this.controller })
            .id('post-video-surface').width('100%').height('100%').objectFit(ImageFit.Contain)
            .autoPlay(false).controls(false).loop(false).focusable(false).hitTestBehavior(HitTestMode.None)
            .accessibilityLevel('no')
            .onPrepared((info: PreparedInfo) => {
              if (this.mounted && !this.failed) {
                this.mediaDuration = Number.isFinite(info.duration) && info.duration > 0 ? info.duration : 0;
                this.prepared = true;
              }
            })
            .onStart(() => {
              // A queued start may arrive after the destination or app lost visibility.
              if (!this.active || !this.mounted || !this.wantsPlayback || this.failed) { this.controller.pause(); }
            })
            .onPause(() => { if (this.mounted) { this.wantsPlayback = false; } })
            .onFinish(() => {
              if (this.mounted && !this.failed) {
                this.wantsPlayback = false;
                this.finished = true;
                if (this.totalSeconds() > 0) { this.playbackPosition = this.totalSeconds(); }
              }
            })
            .onSeeked((info: PlaybackInfo) => { this.updatePosition(info.time); })
            .onUpdate((info: PlaybackInfo) => { this.updatePosition(info.time); })
            .onError(() => { this.failPlayback(); })
        }.width('100%').layoutWeight(1).backgroundColor(Color.Black)
        this.PlayerControls()
      }
    }.id('post-video-player').width('100%').height('100%').backgroundColor($r('app.color.timeline_background'))
  }
}
