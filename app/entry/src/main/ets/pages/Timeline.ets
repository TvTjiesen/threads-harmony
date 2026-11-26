import { router } from '@kit.ArkUI';

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
  @State private wide: boolean = false;
  @State private animationTriggers: number[] = POSTS.map((_post: MockPost) => -1);
  @State private reduceMotion: boolean = false;
  @State private settingsVisible: boolean = false;

  private inform(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message, duration: 1800 });
    } catch (_error) {
      // A transient toast failure must not interrupt the post interaction.
    }
  }

  private animationTriggerFor(id: string): number {
    const index = POSTS.findIndex((post: MockPost) => post.id === id);
    return index >= 0 && !this.reduceMotion ? this.animationTriggers[index] : -1;
  }

  private setReduceMotion(enabled: boolean): void {
    this.reduceMotion = enabled;
    if (enabled) {
      this.animationTriggers = POSTS.map((_post: MockPost) => -1);
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
    nextTriggers[index] = wasLiked || this.reduceMotion ? -1 : nextTriggers[index] + 1;
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
      Row() {
        Column({ space: 4 }) {
          Text('显示与动效').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#242320')
          Text('按你的阅读习惯调整界面').fontSize(13).fontColor('#6D6862')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('完成', { type: ButtonType.Capsule })
          .height(44).padding({ left: 16, right: 16 }).backgroundColor('#292824').fontColor('#FFFFFF')
          .onClick(() => { this.settingsVisible = false; })
      }.width('100%')

      Row({ space: 16 }) {
        Column({ space: 4 }) {
          Text('减少动效').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#2C2A27')
          Text('仅影响本页点赞反馈；当前会话有效').fontSize(12).fontColor('#77736F')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.reduceMotion })
          .accessibilityText('减少动效')
          .onChange((enabled: boolean) => { this.setReduceMotion(enabled); })
      }.width('100%').padding(16).backgroundColor('#F5F3EF').borderRadius(18)
    }
    .width('100%').padding({ left: 22, right: 22, top: 20, bottom: 28 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  PostCard(post: MockPost) {
    Column({ space: 16 }) {
      Row({ space: 12 }) {

        Text(post.name.substring(0, 1)).width(46).height(46).fontSize(18).fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF').textAlign(TextAlign.Center).backgroundColor(post.avatarColor).borderRadius(23)
        Column({ space: 4 }) {
          Text(post.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#20201F')
          Text(`${post.handle}  ·  ${post.time}`).fontSize(12).fontColor('#6D6862').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button(this.followedIds.includes(post.id) ? '已关注' : '关注')
          .height(48).padding({ left: 15, right: 15 }).fontSize(12).fontWeight(FontWeight.Medium).borderRadius(18)
          .backgroundColor(this.followedIds.includes(post.id) ? '#F1EEE9' : '#262522')
          .fontColor(this.followedIds.includes(post.id) ? '#615D57' : '#FFFFFF')
          .accessibilitySelected(this.followedIds.includes(post.id))
          .onClick(() => this.toggleFollow(post.id))
      }.width('100%')

      Text(post.body).fontSize(15).fontColor('#34322F').lineHeight(24).width('100%')
        .textAlign(TextAlign.Start).copyOption(CopyOptions.InApp)

      Row({ space: 0 }) {
        Row({ space: 7 }) {
          Button({ type: ButtonType.Circle, stateEffect: false }) {
            SymbolGlyph(this.likedIds.includes(post.id) ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
              .fontSize(21).fontColor([this.likedIds.includes(post.id) ? '#B53C53' : '#635D56'])
              .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE), this.animationTriggerFor(post.id))
          }.width(48).height(48).buttonStyle(ButtonStyleMode.TEXTUAL)
            .accessibilityText(this.likedIds.includes(post.id) ? '取消点赞' : '点赞')
            .accessibilitySelected(this.likedIds.includes(post.id))
            .onClick(() => this.toggleLike(post.id))
          Text(`${post.likes + (this.likedIds.includes(post.id) ? 1 : 0)}`).fontSize(12).fontColor('#635D56')
        }.layoutWeight(1).justifyContent(FlexAlign.Start)
        Row({ space: 7 }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.message')).fontSize(20).fontColor(['#635D56'])
          }.width(48).height(48).buttonStyle(ButtonStyleMode.TEXTUAL).accessibilityText('回复')
            .onClick(() => { this.inform('回复仅为界面演示，当前不会发送。'); })
          Text(`${post.replies}`).fontSize(12).fontColor('#77736F')
        }.layoutWeight(1).justifyContent(FlexAlign.Center)
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.share')).fontSize(20).fontColor(['#635D56'])
        }.width(48).height(48).buttonStyle(ButtonStyleMode.TEXTUAL).accessibilityText('分享')
          .onClick(() => { this.inform('分享功能尚未接入。'); })
      }.width('100%')
    }
    .width('100%').padding(18).backgroundColor('#FFFFFF').borderRadius(22)
    .border({ width: 1, color: '#ECE8E2' })
    .shadow({ radius: 12, color: '#10000000', offsetX: 0, offsetY: 3 })
    .constraintSize({ maxWidth: 600 })
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text('此刻').fontSize(30).fontWeight(FontWeight.Bold).fontColor('#242320')
          Text('Threads · 本地演示').fontSize(12).fontColor('#6D6862')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('设置', { type: ButtonType.Capsule })
          .height(44).padding({ left: 14, right: 14 }).backgroundColor('#EAE6E0').fontColor('#34322F').fontSize(12)
          .accessibilityText('显示与动效设置')
          .onClick(() => { this.settingsVisible = true; })
        Button('打开网页', { type: ButtonType.Capsule }).height(48).padding({ left: 18, right: 18 })
          .backgroundColor('#292824').fontColor('#FFFFFF').fontSize(13).enabled(!this.openingWeb)
          .onClick(() => { this.openWeb(); })
      }.width('100%').padding({ left: 22, right: 22, top: 18, bottom: 15 })
        .backgroundEffect({ radius: 24, saturation: 1.16, brightness: 1.02, color: '#EEF5F3EF' })

      Text('演示内容不会连接 Threads').fontSize(12).fontColor('#6D6862')
        .width('100%').padding({ left: 22, right: 22, bottom: 14 })

      List({ space: 12 }) {
        ForEach(POSTS, (post: MockPost) => {
          ListItem() {
            this.PostCard(post)
          }
        }, (post: MockPost) => post.id)
      }
      .lanes(this.wide ? 2 : 1, 12)
      .alignListItem(ListItemAlign.Center)
      .cachedCount(2)
      .layoutWeight(1)
      .width('100%')
      .constraintSize({ maxWidth: 1248 })
      .padding({ left: 18, right: 18, bottom: 12 })
      .scrollBar(BarState.Auto)

    }
    .width('100%').height('100%').backgroundColor('#F5F3EF')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const wide = Number(newArea.width) >= 680;
      if (wide !== this.wide) {
        this.wide = wide;
      }
    })
    .bindSheet($$this.settingsVisible, this.SettingsSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      blurStyle: BlurStyle.Thin,
      showClose: false,
      preferType: this.wide ? SheetType.CENTER : SheetType.BOTTOM
    })
  }
}
