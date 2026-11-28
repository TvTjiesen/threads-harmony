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
  onPublicThreads: () => void = () => {};

  private readonly segments: SegmentButtonV2Items = new SegmentButtonV2Items([{ text: '帖子' }, { text: '作者' }]);
  private readonly searchController: SearchController = new SearchController();
  private readonly resultScroller: Scroller = new Scroller();

  private changeQuery(value: string): void {
    if (this.query !== value) {
      this.onQuery(value);
      this.resultScroller.scrollToIndex(0, false, ScrollAlign.START);
    }
  }

  private submitQuery(value: string): void {
    this.searchController.stopEditing();
    const query = value.trim();
    if (query !== this.query) { this.onQuery(query); }
    this.resultScroller.scrollToIndex(0, false, ScrollAlign.START);
  }

  private selectMode(value: number): void {
    if (this.mode !== value) {
      this.onMode(value);
      this.searchController.stopEditing();
      this.resultScroller.scrollToIndex(0, false, ScrollAlign.START);
    }
  }

  private selectTopic(topic: string): void {
    this.searchController.stopEditing();
    this.onTopic(topic);
    this.resultScroller.scrollToIndex(0, false, ScrollAlign.START);
  }

  private clearAndEdit(): void {
    this.changeQuery('');
    try {
      this.getUIContext().getFocusController().requestFocus('discovery-search');
    } catch (_error) {
      // The tab can lose focus while its results are being replaced.
    }
  }

  @Builder
  SearchBar() {
    Column({ space: 8 }) {
      Text('发现').fontSize('28fp').fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
      Search({ value: this.query, placeholder: this.mode === 1 ? '搜索作者昵称或用户名' : '搜索帖子关键词',
        controller: this.searchController })
        .id('discovery-search').width('100%').constraintSize({ minHeight: 48 }).maxLength(120)
        .textFont({ size: '16fp' }).placeholderFont({ size: '16fp' })
        .backgroundColor($r('app.color.timeline_surface_muted')).fontColor($r('app.color.timeline_text_body'))
        .placeholderColor($r('app.color.timeline_text_secondary'))
        .searchButton('搜索', { fontSize: '15fp', fontColor: $r('app.color.timeline_text_primary') })
        .cancelButton({ style: CancelButtonStyle.INPUT })
        .accessibilityText(this.mode === 1 ? '搜索示例作者' : '搜索本机和演示帖子')
        .onChange((value: string) => this.changeQuery(value))
        .onSubmit((value: string) => this.submitQuery(value))
      TabSegmentButtonV2({ items: this.segments, selectedIndex: this.mode, itemMaxFontScale: 2,
        itemMinHeight: LengthMetrics.vp(48), $selectedIndex: (value: number) => this.selectMode(value) })
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
            .onClick(() => this.selectTopic(topic))
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
    Column({ space: 6 }) {
      Text(this.query.trim().length > 0 ? (this.mode === 1 ? '未找到匹配的作者' : '未找到匹配的帖子') :
        (this.mode === 1 ? '暂无示例作者' : '暂无可浏览的帖子'))
        .id('discovery-empty').width('100%').fontSize('17fp').fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.timeline_text_primary'))
      if (this.query.trim().length > 0) {
        Text(`没有「${this.query.trim()}」的结果。${this.mode === 1 ? '试试昵称或用户名。' : '试试更短的关键词。'}`)
          .width('100%').wordBreak(WordBreak.BREAK_WORD).fontSize('14fp')
          .fontColor($r('app.color.timeline_text_secondary'))
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(4) } }) {
          Button('清除搜索').id('discovery-clear-query').buttonStyle(ButtonStyleMode.TEXTUAL)
            .constraintSize({ minHeight: 48 }).fontColor($r('app.color.timeline_text_primary'))
            .onClick(() => this.clearAndEdit())
          Button(this.mode === 1 ? '改搜帖子' : '改搜作者').id('discovery-switch-mode').buttonStyle(ButtonStyleMode.TEXTUAL)
            .constraintSize({ minHeight: 48 }).fontColor($r('app.color.timeline_text_body'))
            .onClick(() => this.selectMode(this.mode === 1 ? 0 : 1))
        }.width('100%')
      } else if (this.mode === 0 && this.topics.length > 0) {
        Text('可以从上面的本机话题开始探索。').width('100%').fontSize('14fp')
          .fontColor($r('app.color.timeline_text_secondary'))
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 12, bottom: 16 })
  }

  @Builder
  ScopeAndStatus() {
    Column({ space: 6 }) {
      this.status()
      Text(this.mode === 1 ? '仅搜索示例作者，不连接 Threads 账号。' : '仅搜索本机与演示帖子，不含 Threads 站内结果。')
        .width('100%').fontSize('13fp').fontColor($r('app.color.timeline_text_secondary'))
      if (this.query.trim().length > 0 && (this.mode === 0 ? this.hasPosts : this.authors.length > 0)) {
        Button('清除搜索').id('discovery-clear-results').buttonStyle(ButtonStyleMode.TEXTUAL)
          .constraintSize({ minHeight: 48 }).fontColor($r('app.color.timeline_text_primary'))
          .onClick(() => { this.searchController.stopEditing(); this.changeQuery(''); })
      } else if (this.mode === 0 && this.query.trim().length === 0 && this.topics.length > 0) {
        this.TopicChooser()
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 8, bottom: 4 })
  }

  @Builder
  PublicContentLink() {
    Button('Threads 公开内容 · 开发联调').id('discovery-public-threads').buttonStyle(ButtonStyleMode.TEXTUAL)
      .fontColor($r('app.color.timeline_text_secondary')).constraintSize({ minHeight: 48 })
      .onClick(() => { this.searchController.stopEditing(); this.onPublicThreads(); })
  }

  build() {
    Column() {
      Column() {
        this.SearchBar()
        Divider().strokeWidth(0.5).color($r('app.color.timeline_border'))
        List({ scroller: this.resultScroller, space: 8 }) {
          ListItem() { this.ScopeAndStatus() }
          if (this.query.trim().length === 0) {
            ListItem() { this.PublicContentLink() }
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
          if (this.query.trim().length > 0) {
            ListItem() { this.PublicContentLink() }
          }
        }.id('discovery-results').width('100%').layoutWeight(1).scrollBar(BarState.Auto)
          .padding({ bottom: 16 })
      }.width('100%').height('100%').constraintSize({ maxWidth: 640 }).padding({ left: 18, right: 18 })
    }.width('100%').height('100%').backgroundColor($r('app.color.timeline_surface'))
  }
}
