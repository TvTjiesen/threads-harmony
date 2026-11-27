import { LengthMetrics, SegmentButtonV2Items, TabSegmentButtonV2 } from '@kit.ArkUI';

export interface DiscoveryAuthor {
  id: string;
  name: string;
  handle: string;
  avatarColor: string;
  followed: boolean;
  postCount: number;
}

@Builder
function EmptyDiscoveryStatus() {}

@Component
export struct DiscoveryPane {
  @Prop query: string = '';
  @Prop mode: number = 0;
  @Prop authors: DiscoveryAuthor[] = [];
  @Prop topics: string[] = [];
  @Prop hasPosts: boolean = false;
  @BuilderParam posts: () => void;
  @BuilderParam status: () => void = EmptyDiscoveryStatus;
  onQuery: (value: string) => void = (_value: string): void => {};
  onMode: (value: number) => void = (_value: number): void => {};
  onAuthor: (id: string) => void = (_id: string): void => {};
  onTopic: (topic: string) => void = (_topic: string): void => {};

  private readonly segments: SegmentButtonV2Items = new SegmentButtonV2Items([{ text: '帖子' }, { text: '作者' }]);

  @Builder
  SearchBar() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('发现').fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
          .layoutWeight(1)
        Text('本机预览').fontSize(12).fontColor($r('app.color.timeline_text_secondary'))
      }.width('100%')
      Search({ value: this.query, placeholder: '搜索帖子或作者' })
        .id('discovery-search').width('100%').constraintSize({ minHeight: 48 }).maxLength(120)
        .backgroundColor($r('app.color.timeline_surface_muted')).fontColor($r('app.color.timeline_text_body'))
        .placeholderColor($r('app.color.timeline_text_secondary')).accessibilityText('搜索本机帖子或示例作者')
        .onChange((value: string) => this.onQuery(value))
      TabSegmentButtonV2({ items: this.segments, selectedIndex: this.mode, itemMaxFontScale: 2,
        itemMinHeight: LengthMetrics.vp(44), $selectedIndex: (value: number) => this.onMode(value) })
        .id('discovery-mode').width('100%').constraintSize({ maxWidth: 280 })
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 10, bottom: 10 })
  }

  @Builder
  TopicChooser() {
    Column({ space: 6 }) {
      Text('探索话题').fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(4) } }) {
        ForEach(this.topics, (topic: string) => {
          Button('# ' + topic, { type: ButtonType.Capsule })
            .id('discovery-topic-' + topic).constraintSize({ minHeight: 48, minWidth: 48, maxWidth: '100%' })
            .padding({ left: 12, right: 12 }).fontSize(14).fontColor($r('app.color.timeline_text_body'))
            .backgroundColor($r('app.color.timeline_toolbar_button')).accessibilityText('搜索话题 ' + topic)
            .onClick(() => this.onTopic(topic))
        }, (topic: string) => topic)
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 10, bottom: 8 })
  }

  @Builder
  AuthorRow(author: DiscoveryAuthor) {
    Column() {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 12 }) {
          Text(author.name.substring(0, 1)).width(40).height(40).borderRadius(20).fontSize('20vp')
            .fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
            .fontColor($r('app.color.timeline_on_avatar')).backgroundColor(author.avatarColor).accessibilityLevel('no')
          Column({ space: 2 }) {
            Text(author.name).fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
              .wordBreak(WordBreak.BREAK_WORD)
            Text(author.handle).fontSize(14).fontColor($r('app.color.timeline_text_secondary'))
              .wordBreak(WordBreak.BREAK_WORD)
            Text(`${author.postCount} 条帖子${author.followed ? ' · 已关注' : ''}`).fontSize(13)
              .fontColor($r('app.color.timeline_text_secondary'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%')
      }.id('discovery-author-' + author.id).width('100%').constraintSize({ minHeight: 48 })
        .buttonStyle(ButtonStyleMode.TEXTUAL).backgroundColor(Color.Transparent)
        .padding({ left: 0, right: 0, top: 10, bottom: 10 })
        .accessibilityText(`${author.name}，${author.handle}，${author.postCount} 条帖子${author.followed ? '，已关注' : ''}`)
        .accessibilityDescription('查看作者主页').onClick(() => this.onAuthor(author.id))
      Divider().strokeWidth(0.5).color($r('app.color.timeline_border'))
    }.width('100%')
  }

  @Builder
  EmptyResult() {
    Column({ space: 4 }) {
      Text(this.mode === 1 ? '未找到匹配的作者' : '未找到匹配的帖子')
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
      Text(this.mode === 1 ? '试试作者昵称或用户名。' : '试试正文中的其他关键词。')
        .fontSize(14).fontColor($r('app.color.timeline_text_secondary'))
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 16, bottom: 16 })
  }

  build() {
    Column() {
      Column() {
        this.SearchBar()
        Divider().strokeWidth(0.5).color($r('app.color.timeline_border'))
        List({ space: 8 }) {
          ListItem() {
            Column({ space: 6 }) {
              this.status()
              if (this.mode === 0 && this.query.trim().length === 0 && this.topics.length > 0) {
                this.TopicChooser()
              }
            }.width('100%').alignItems(HorizontalAlign.Start)
          }
          if (this.mode === 1 && this.authors.length > 0) {
            ForEach(this.authors, (author: DiscoveryAuthor) => {
              ListItem() { this.AuthorRow(author) }
            }, (author: DiscoveryAuthor) => `${author.id}:${author.followed}:${author.postCount}`)
          } else if (this.mode === 0 && this.hasPosts) {
            this.posts()
          } else {
            ListItem() { this.EmptyResult() }
          }
        }.id('discovery-results').width('100%').layoutWeight(1).scrollBar(BarState.Auto)
          .padding({ bottom: 16 })
      }.width('100%').height('100%').constraintSize({ maxWidth: 640 }).padding({ left: 18, right: 18 })
    }.width('100%').height('100%').backgroundColor($r('app.color.timeline_surface'))
  }
}
