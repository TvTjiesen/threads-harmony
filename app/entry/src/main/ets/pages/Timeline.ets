import { accessibility } from '@kit.AccessibilityKit';
import { preferences } from '@kit.ArkData';
import { FrameCallback, LengthMetrics, router } from '@kit.ArkUI';

const LARGE_TEXT_SCALE = 1.4;
const WIDE_VIEWPORT = 680;
const MAX_LIST_WIDTH = 1248;

interface ReadingAnchor {
  postId: string;
  clipped: number;
}

class LayoutFrame extends FrameCallback {
  private readonly task: () => void;

  constructor(task: () => void) {
    super();
    this.task = task;
  }

  onIdle(_timeLeftInNano: number): void {
    this.task();
  }
}
const DISPLAY_PREFERENCES = 'timeline_display';
const REDUCE_MOTION_KEY = 'reduce_motion';

interface MockPost {
  id: string;
  name: string;
  handle: string;
  time: string;
  body: string;
  replies: number;
  likes: number;
  avatarColor: string;
}

const POSTS: MockPost[] = [
  { id: 'p1', name: '林间散步', handle: '@walks.daily', time: '2 小时', body: '今天把节奏放慢一点。阳光、咖啡，还有一段没有目的地的散步。', replies: 12, likes: 86, avatarColor: '#8B6F5A' },
  { id: 'p2', name: '小岛来信', handle: '@island.notes', time: '4 小时', body: '做一个好用的客户端，先从认真照顾每一个细节开始。你最在意阅读、发布，还是切换设备时的连续感？', replies: 7, likes: 43, avatarColor: '#4A7B78' },
  { id: 'p3', name: '像素与纸', handle: '@pixels.and.paper', time: '昨天', body: '折叠屏合上时是一条舒适的时间线，展开后自然变成双栏。界面应该跟着设备形态长大。', replies: 19, likes: 122, avatarColor: '#776B9A' },
  { id: 'p4', name: '慢慢烘焙', handle: '@slow.bake', time: '昨天', body: '周末实验了新的酸种配方，厨房里全是面包出炉的香气。', replies: 5, likes: 31, avatarColor: '#C27B53' },
  { id: 'p5', name: '城市观察员', handle: '@city.notes', time: '2 天', body: '通勤路上看到一棵树冒出新芽，春天大概真的快来了。', replies: 9, likes: 64, avatarColor: '#6E8A62' },
  { id: 'p6', name: '周末书架', handle: '@weekend.books', time: '2 天', body: '在旧书里发现一张二十年前的车票。原来读到同一页的人，也可以离得这么远。', replies: 3, likes: 17, avatarColor: '#835B69' },
  { id: 'p7', name: '夜归电台', handle: '@night.radio', time: '3 天', body: '今晚的歌单只有三首，刚好够走完从车站回家的路。', replies: 2, likes: 23, avatarColor: '#485E81' },
  { id: 'p8', name: '山下邮局', handle: '@hill.post', time: '3 天', body: '把这周拍到的云印成四张明信片，寄给好久没见面的朋友。', replies: 6, likes: 39, avatarColor: '#866844' }
];

@Entry
@Component
struct Timeline {
  @State private likedIds: string[] = [];
  @State private followedIds: string[] = [];
  @State private openingWeb: boolean = false;
  @State private viewportWidth: number = 0;
  @StorageProp('timelineFontScale') @Watch('onReadingLayoutChange') private fontScale: number = 1;
  @State private animationTriggers: number[] = POSTS.map((_post: MockPost) => -1);
  @State private reduceMotion: boolean = false;
  @State private systemReducesMotion: boolean = false;
  @State private motionPreferenceReady: boolean = false;
  @State private motionPreferenceSaving: boolean = false;
  @State private motionPreferenceWarning: string = '';
  @State private settingsVisible: boolean = false;
  private readonly timelineScroller: Scroller = new Scroller();
  private firstVisibleIndex: number = 0;
  private readingAnchor: ReadingAnchor = { postId: '', clipped: 0 };
  private restorePending: boolean = false;
  private restoreScheduled: boolean = false;
  private timelineVisible: boolean = false;
  private watchingSystemMotion: boolean = false;
  private readonly systemMotionListener = (enabled: boolean): void => {
    this.systemReducesMotion = enabled;
    if (enabled) {
      this.resetMotionFeedback();
    }
  };

  aboutToAppear(): void {
    try {
      this.systemMotionListener(accessibility.isAnimationReduceEnabledSync());
      accessibility.onAnimationReduceStateChange(this.systemMotionListener);
      this.watchingSystemMotion = true;
    } catch (_error) {
      // The local preference still works if this device cannot report system motion settings.
    }
    this.loadMotionPreference();
  }

  aboutToDisappear(): void {
    if (this.watchingSystemMotion) {
      this.watchingSystemMotion = false;
      try {
        accessibility.offAnimationReduceStateChange(this.systemMotionListener);
      } catch (_error) {
        // Keep the rest of the page teardown independent of the system service.
      }
    }
  }

  onPageShow(): void {
    this.timelineVisible = true;
    if (this.restorePending) {
      this.scheduleReadingRestore();
    }
  }

  onPageHide(): void {
    this.timelineVisible = false;
  }

  private toolbarInList(): boolean {
    return this.fontScale >= LARGE_TEXT_SCALE;
  }

  private readingLaneCount(): number {
    return this.viewportWidth >= WIDE_VIEWPORT && !this.toolbarInList() ? 2 : 1;
  }

  private rememberReadingPosition(): void {
    if (!this.timelineVisible || this.restorePending) {
      return;
    }
    const index = this.firstVisibleIndex;
    try {
      const offset = this.timelineScroller.offset();
      if (offset === undefined || index < 0) {
        return;
      }
      const post = POSTS[index - (this.toolbarInList() ? 1 : 0)];
      if (offset.yOffset <= 1 || (index === 0 && post === undefined)) {
        this.readingAnchor = { postId: '', clipped: 0 };
      } else if (post !== undefined) {
        const rect = this.timelineScroller.getItemRect(index);
        if (rect.height > 0) {
          this.readingAnchor = { postId: post.id, clipped: Math.max(0, -rect.y) };
        }
      }
    } catch (_error) {
      // The layout can be detached during a window transition.
    }
  }

  private onReadingLayoutChange(): void {
    this.restorePending = true;
    this.scheduleReadingRestore();
  }

  private scheduleReadingRestore(): void {
    if (!this.timelineVisible || this.restoreScheduled) {
      return;
    }
    this.restoreScheduled = true;
    this.getUIContext().postFrameCallback(new LayoutFrame(() => {
      this.restoreScheduled = false;
      if (!this.timelineVisible || !this.restorePending) {
        return;
      }
      this.restoreReadingPosition();
    }));
  }

  private restoreReadingPosition(): void {
    const anchor = this.readingAnchor;
    try {
      if (anchor.postId === '') {
        if ((this.timelineScroller.offset()?.yOffset ?? 0) > 1) {
          this.timelineScroller.scrollToIndex(0, false, ScrollAlign.START);
        }
        return;
      }
      const postIndex = POSTS.findIndex((post: MockPost) => post.id === anchor.postId);
      if (postIndex < 0) {
        return;
      }
      const index = postIndex + (this.toolbarInList() ? 1 : 0);
      const rect = this.timelineScroller.getItemRect(index);
      const clipped = rect.height > 0 ? Math.min(anchor.clipped, rect.height / 2) : 0;
      if (rect.height <= 0 || Math.abs(rect.y + clipped) > 1) {
        this.timelineScroller.scrollToIndex(index, false, ScrollAlign.START, { extraOffset: LengthMetrics.vp(clipped) });
      }
    } catch (_error) {
      // A different window may have detached the list before this frame.
    } finally {
      this.restorePending = false;
    }
  }

  private async displayPreferences(): Promise<preferences.Preferences> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('Timeline host context unavailable');
    }
    return preferences.getPreferences(context, { name: DISPLAY_PREFERENCES });
  }

  private async loadMotionPreference(): Promise<void> {
    try {
      const store = await this.displayPreferences();
      this.setReduceMotion(await store.get(REDUCE_MOTION_KEY, false) === true);
    } catch (_error) {
      this.motionPreferenceWarning = '无法读取已保存的偏好。';
    } finally {
      this.motionPreferenceReady = true;
    }
  }

  private async updateMotionPreference(enabled: boolean): Promise<void> {
    if (!this.motionPreferenceReady || this.motionPreferenceSaving || this.reduceMotion === enabled) {
      return;
    }
    this.setReduceMotion(enabled);
    this.motionPreferenceSaving = true;
    this.motionPreferenceWarning = '';
    try {
      const store = await this.displayPreferences();
      await store.put(REDUCE_MOTION_KEY, enabled);
      await store.flush();
    } catch (_error) {
      this.motionPreferenceWarning = '偏好未能保存，本次仍然生效。';
    } finally {
      this.motionPreferenceSaving = false;
    }
  }

  private inform(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message, duration: 1800 });
    } catch (_error) {
      // A transient toast failure must not interrupt the post interaction.
    }
  }

  private allowsMotionFeedback(): boolean {
    return this.motionPreferenceReady && !this.reduceMotion && !this.systemReducesMotion;
  }

  private animationTriggerFor(id: string): number {
    const index = POSTS.findIndex((post: MockPost) => post.id === id);
    return index >= 0 && this.allowsMotionFeedback() ? this.animationTriggers[index] : -1;
  }

  private resetMotionFeedback(): void {
    this.animationTriggers = POSTS.map((_post: MockPost) => -1);
  }

  private setReduceMotion(enabled: boolean): void {
    this.reduceMotion = enabled;
    if (enabled) {
      this.resetMotionFeedback();
    }
  }

  private async openWeb(): Promise<void> {
    if (this.openingWeb) {
      return;
    }
    this.openingWeb = true;
    try {
      await router.pushUrl({ url: 'pages/Index' });
    } catch (_error) {
      this.inform('网页暂时无法打开，请稍后重试。');
    } finally {
      this.openingWeb = false;
    }
  }

  private toggleLike(id: string): void {
    const index = POSTS.findIndex((post: MockPost) => post.id === id);
    if (index < 0) {
      return;
    }
    const wasLiked = this.likedIds.includes(id);
    this.likedIds = wasLiked
      ? this.likedIds.filter((item: string) => item !== id)
      : [...this.likedIds, id];
    const nextTriggers = [...this.animationTriggers];
    nextTriggers[index] = wasLiked || !this.allowsMotionFeedback() ? -1 : nextTriggers[index] + 1;
    this.animationTriggers = nextTriggers;
  }

  private toggleFollow(id: string): void {
    this.followedIds = this.followedIds.includes(id)
      ? this.followedIds.filter((item: string) => item !== id)
      : [...this.followedIds, id];
  }

  @Builder
  SettingsSheet() {
    Column({ space: 18 }) {
      Column({ space: 12 }) {
        Column({ space: 4 }) {
          Text('显示与动效').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
          Text('按你的阅读习惯调整界面').fontSize(13).fontColor($r('app.color.timeline_text_secondary'))
        }.alignItems(HorizontalAlign.Start).width('100%')
        Button('完成', { type: ButtonType.Capsule })
          .width('100%').constraintSize({ minHeight: 44 }).padding({ left: 16, right: 16, top: 10, bottom: 10 }).backgroundColor($r('app.color.timeline_action')).fontColor($r('app.color.timeline_on_action'))
          .onClick(() => { this.settingsVisible = false; })
      }.width('100%')

      Row({ space: 16 }) {
        Column({ space: 4 }) {
          Text('减少动效').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.timeline_text_primary'))
          Text(this.systemReducesMotion ? '系统已减少动效；点赞不会播放弹跳。' : '仅影响本页点赞弹跳；偏好保存在本机。')
            .fontSize(12).fontColor($r('app.color.timeline_text_muted'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.reduceMotion })
          .accessibilityText('减少动效')
          .enabled(this.motionPreferenceReady && !this.motionPreferenceSaving)
          .onChange((enabled: boolean) => { this.updateMotionPreference(enabled); })
      }.width('100%').padding(16).backgroundColor($r('app.color.timeline_background')).borderRadius(18)
      if (this.motionPreferenceWarning.length > 0) {
        Text(this.motionPreferenceWarning).fontSize(12).fontColor($r('app.color.timeline_text_secondary')).width('100%')
      }
    }
    .width('100%').padding({ left: 22, right: 22, top: 20, bottom: 28 })
    .backgroundColor($r('app.color.timeline_surface'))
  }

  @Builder
  FollowAction(post: MockPost) {
    Button(this.followedIds.includes(post.id) ? '已关注' : '关注')
      .constraintSize({ minHeight: 48 }).padding({ left: 15, right: 15, top: 10, bottom: 10 }).fontSize(12).fontWeight(FontWeight.Medium).borderRadius(18)
      .backgroundColor(this.followedIds.includes(post.id) ? $r('app.color.timeline_surface_muted') : $r('app.color.timeline_action'))
      .fontColor(this.followedIds.includes(post.id) ? $r('app.color.timeline_action_muted') : $r('app.color.timeline_on_action'))
      .accessibilitySelected(this.followedIds.includes(post.id))
      .onClick(() => this.toggleFollow(post.id))
  }

  @Builder
  PostCard(post: MockPost) {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        Text(post.name.substring(0, 1)).width(46).height(46).fontSize('18vp').fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.timeline_on_avatar')).textAlign(TextAlign.Center).backgroundColor(post.avatarColor).borderRadius(23)
          .accessibilityLevel('no')
        Column({ space: 4 }) {
          Text(post.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
          Text(`${post.handle}  ·  ${post.time}`).fontSize(12).fontColor($r('app.color.timeline_text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        if (this.fontScale < LARGE_TEXT_SCALE && this.viewportWidth >= 360) {
          this.FollowAction(post)
        }
      }.width('100%')
      if (this.fontScale >= LARGE_TEXT_SCALE || this.viewportWidth < 360) {
        Row() { this.FollowAction(post) }.width('100%').justifyContent(FlexAlign.End)
      }

      Text(post.body).fontSize(15).fontColor($r('app.color.timeline_text_body')).width('100%')
        .textAlign(TextAlign.Start).copyOption(CopyOptions.InApp)

      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center, justifyContent: FlexAlign.SpaceBetween,
        space: { cross: LengthMetrics.vp(6) } }) {
        Row({ space: 4 }) {
          Button({ type: ButtonType.Circle, stateEffect: false }) {
            if (this.allowsMotionFeedback()) {
              SymbolGlyph(this.likedIds.includes(post.id) ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                .fontSize(21).fontColor([this.likedIds.includes(post.id) ? $r('app.color.timeline_like') : $r('app.color.timeline_text_secondary')])
                .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE), this.animationTriggerFor(post.id))
            } else {
              SymbolGlyph(this.likedIds.includes(post.id) ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                .fontSize(21).fontColor([this.likedIds.includes(post.id) ? $r('app.color.timeline_like') : $r('app.color.timeline_text_secondary')])
            }
          }.width(48).height(48).buttonStyle(ButtonStyleMode.TEXTUAL)
            .accessibilityText(this.likedIds.includes(post.id) ? '取消点赞' : '点赞')
            .accessibilitySelected(this.likedIds.includes(post.id))
            .onClick(() => this.toggleLike(post.id))
          Text(`${post.likes + (this.likedIds.includes(post.id) ? 1 : 0)}`).fontSize(12).fontColor($r('app.color.timeline_text_secondary'))
        }
        Row({ space: 4 }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.message')).fontSize(20).fontColor([$r('app.color.timeline_text_secondary')])
          }.width(48).height(48).buttonStyle(ButtonStyleMode.TEXTUAL).accessibilityText('回复')
            .onClick(() => { this.inform('回复仅为界面演示，当前不会发送。'); })
          Text(`${post.replies}`).fontSize(12).fontColor($r('app.color.timeline_text_muted'))
        }
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.share')).fontSize(20).fontColor([$r('app.color.timeline_text_secondary')])
        }.width(48).height(48).buttonStyle(ButtonStyleMode.TEXTUAL).accessibilityText('分享')
          .onClick(() => { this.inform('分享功能尚未接入。'); })
      }.width('100%')
    }
    .width('100%').padding(18).backgroundColor($r('app.color.timeline_surface')).borderRadius(22)
    .border({ width: 1, color: $r('app.color.timeline_border') })
    .shadow({ radius: 12, color: $r('app.color.timeline_shadow'), offsetX: 0, offsetY: 3 })
    .constraintSize({ maxWidth: 600 })
  }

  @Builder
  Toolbar() {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center,
      space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
      Column({ space: 3 }) {
        Text('此刻').fontSize(30).fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
        Text('Threads · 本地演示').fontSize(12).fontColor($r('app.color.timeline_text_secondary'))
      }.alignItems(HorizontalAlign.Start).flexGrow(1)
        .width(this.fontScale >= LARGE_TEXT_SCALE ? '100%' : 'auto')
      Button('设置', { type: ButtonType.Capsule })
        .constraintSize({ minHeight: 44 }).padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.timeline_toolbar_button')).fontColor($r('app.color.timeline_text_body')).fontSize(12)
        .accessibilityText('显示与动效设置')
        .onClick(() => { this.settingsVisible = true; })
      Button('打开网页', { type: ButtonType.Capsule }).constraintSize({ minHeight: 48 }).padding({ left: 18, right: 18, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.timeline_action')).fontColor($r('app.color.timeline_on_action')).fontSize(13).enabled(!this.openingWeb)
        .onClick(() => { this.openWeb(); })
    }.width('100%').padding({ left: 22, right: 22, top: 18, bottom: 15 })
  }

  build() {
    Column() {
      if (!this.toolbarInList()) {
        Column() { this.Toolbar() }.width('100%')
          .backgroundEffect({ radius: 24, saturation: 1.16, brightness: 1.02, color: $r('app.color.timeline_header_overlay') })
        Text('演示内容不会连接 Threads').fontSize(12).fontColor($r('app.color.timeline_text_secondary'))
          .width('100%').padding({ left: 22, right: 22, bottom: 14 })
      }

      List({ space: 12, scroller: this.timelineScroller }) {
        if (this.toolbarInList()) {
          ListItem() {
            Column() {
              this.Toolbar()
              Text('演示内容不会连接 Threads').fontSize(12).fontColor($r('app.color.timeline_text_secondary'))
                .width('100%').padding({ left: 22, right: 22, bottom: 14 })
            }.width('100%').constraintSize({ maxWidth: 600 })
          }
        }
        ForEach(POSTS, (post: MockPost) => {
          ListItem() {
            this.PostCard(post)
          }
        }, (post: MockPost) => post.id)
      }
      .lanes(this.readingLaneCount(), 12)
      .alignListItem(ListItemAlign.Center)
      .cachedCount(2)
      .layoutWeight(1)
      .width('100%')
      .constraintSize({ maxWidth: MAX_LIST_WIDTH })
      .padding({ left: 18, right: 18, bottom: 12 })
      .scrollBar(BarState.Auto)
      .onScrollIndex((start: number) => {
        this.firstVisibleIndex = start;
      })
      .onDidScroll((_offset: number, state: ScrollState) => {
        if (state !== ScrollState.Idle) {
          this.rememberReadingPosition();
        }
      })
      .onScrollStop(() => this.rememberReadingPosition())
    }
    .width('100%').height('100%').backgroundColor($r('app.color.timeline_background'))
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const width = Number(newArea.width);
      if (Number.isFinite(width) && width > 0 && width !== this.viewportWidth) {
        const previousWidth = this.viewportWidth;
        this.viewportWidth = width;
        if (previousWidth > 0 && Math.min(previousWidth, MAX_LIST_WIDTH) !== Math.min(width, MAX_LIST_WIDTH)) {
          this.onReadingLayoutChange();
        }
      }
    })
    .bindSheet($$this.settingsVisible, this.SettingsSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      blurStyle: BlurStyle.Thin,
      showClose: false,
      preferType: this.viewportWidth >= 680 ? SheetType.CENTER : SheetType.BOTTOM
    })
  }
}
