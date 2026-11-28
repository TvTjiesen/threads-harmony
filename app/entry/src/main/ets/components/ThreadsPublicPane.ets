import { LengthMetrics, SegmentButtonV2Items, TabSegmentButtonV2 } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { isOfficialPostLink, PublicPost, requestThreadsPosts } from '../model/ThreadsReader';

@Component
export struct ThreadsPublicPane {
  onClose: () => void = () => {};
  @State private query: string = '';
  @State private mode: number = 0;
  @State private posts: PublicPost[] = [];
  @State private cursor: string = '';
  @State private busy: boolean = false;
  @State private hasResult: boolean = false;
  @State private notice: string = '';
  @State private appendNotice: string = '';
  @State private linkNotice: string = '';
  private serial: number = 0;
  private readonly searchController: SearchController = new SearchController();
  private readonly modes: SegmentButtonV2Items = new SegmentButtonV2Items([{ text: '关键词' }, { text: '公开用户名' }]);

  aboutToDisappear(): void {
    this.serial += 1;
  }

  private clearResults(): void {
    this.serial += 1;
    this.posts = [];
    this.cursor = '';
    this.notice = '';
    this.appendNotice = '';
    this.linkNotice = '';
    this.busy = false;
    this.hasResult = false;
  }

  private async load(append: boolean): Promise<void> {
    if (this.busy || !this.query.trim() || (append && !this.cursor)) { return; }
    if (!append) { this.searchController.stopEditing(); }
    const attempt = ++this.serial;
    const after = append ? this.cursor : '';
    this.busy = true;
    this.notice = '';
    this.appendNotice = '';
    this.linkNotice = '';
    if (!append) {
      this.posts = [];
      this.cursor = '';
      this.hasResult = false;
    }
    try {
      const page = await requestThreadsPosts(this.query, this.mode === 1, after);
      if (attempt !== this.serial) { return; }
      if (page.error) {
        if (append) { this.appendNotice = page.error; } else { this.notice = page.error; }
        return;
      }
      const combined = this.posts.slice();
      for (const item of page.posts) {
        if (combined.length >= 100) { break; }
        if (!combined.some((existing: PublicPost) => existing.id === item.id)) { combined.push(item); }
      }
      this.posts = combined;
      this.cursor = combined.length < 100 && page.nextCursor !== after ? page.nextCursor : '';
      this.hasResult = true;
    } catch (_error) {
      if (attempt === this.serial) {
        if (append) { this.appendNotice = '未能读取下一页，已加载的帖子仍在。'; }
        else { this.notice = '请求暂未完成，请重试。'; }
      }
    } finally {
      if (attempt === this.serial) { this.busy = false; }
    }
  }

  private async openPost(link: string): Promise<void> {
    if (!isOfficialPostLink(link)) { return; }
    this.linkNotice = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (context === undefined) { throw new Error('No UI context'); }
      await context.openLink(link, { appLinkingOnly: false });
    } catch (_error) {
      this.linkNotice = '系统暂时无法打开这条原帖。';
    }
  }

  @Builder
  ReaderHeader() {
    Column({ space: 10 }) {
      Button('返回').id('threads-public-back').buttonStyle(ButtonStyleMode.TEXTUAL)
        .fontColor($r('app.color.timeline_text_body')).constraintSize({ minHeight: 48 }).onClick(() => this.onClose())
      Text('Threads 公开内容').width('100%').fontSize('28fp').fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.timeline_text_primary'))
      Text('官方接口 · 开发联调 · 只读。与本机帖子分开，不是「为你」或「关注中」。')
        .width('100%').fontSize('14fp').fontColor($r('app.color.timeline_text_secondary'))
      TabSegmentButtonV2({ items: this.modes, selectedIndex: this.mode, itemMaxFontScale: 2,
        itemMinHeight: LengthMetrics.vp(44), $selectedIndex: (value: number) => {
          if (value !== this.mode) { this.mode = value; this.query = ''; this.clearResults(); }
        } }).width('100%').constraintSize({ maxWidth: 360 }).id('threads-public-mode')
      Search({ value: this.query, placeholder: this.mode === 1 ? '例如 @threads' : '输入关键词', controller: this.searchController })
        .id('threads-public-query').width('100%').constraintSize({ minHeight: 48 }).maxLength(120)
        .fontColor($r('app.color.timeline_text_body')).backgroundColor($r('app.color.timeline_surface_muted'))
        .onChange((value: string) => { if (value !== this.query) { this.query = value; this.clearResults(); } })
        .onSubmit(() => { this.load(false); })
      Button(this.busy ? '读取中…' : '读取公开帖子').id('threads-public-submit').constraintSize({ minHeight: 48 })
        .enabled(!this.busy && this.query.trim().length > 0).backgroundColor($r('app.color.timeline_action'))
        .fontColor($r('app.color.timeline_on_action')).onClick(() => { this.load(false); })
      if (this.notice) {
        Text(this.notice).id('threads-public-error').width('100%').fontSize('15fp')
          .fontColor($r('app.color.timeline_text_primary')).accessibilityLevel('yes')
      } else if (this.hasResult && this.posts.length === 0 && !this.busy) {
        Text('没有匹配的公开帖子。').fontSize('15fp').fontColor($r('app.color.timeline_text_secondary'))
      }
      if (this.linkNotice) {
        Text(this.linkNotice).fontSize('14fp').fontColor($r('app.color.timeline_text_secondary'))
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  PostRow(post: PublicPost) {
    Column({ space: 7 }) {
      Text('@' + post.username).fontSize('16fp').fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
      if (post.timestamp.length >= 10) {
        Text(post.timestamp.slice(0, 10)).fontSize('12fp').fontColor($r('app.color.timeline_text_secondary'))
      }
      Text(post.text || '此帖没有可显示的正文。').width('100%').wordBreak(WordBreak.BREAK_WORD)
        .fontSize('16fp').fontColor($r('app.color.timeline_text_body'))
      if (post.permalink) {
        Button('在系统浏览器查看原帖').buttonStyle(ButtonStyleMode.TEXTUAL).constraintSize({ minHeight: 48 })
          .fontColor($r('app.color.timeline_text_primary')).onClick(() => { this.openPost(post.permalink); })
      }
      Divider().color($r('app.color.timeline_border'))
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 8, bottom: 7 })
  }

  build() {
    Column() {
      List({ space: 10 }) {
        ListItem() { this.ReaderHeader() }
        ForEach(this.posts, (post: PublicPost) => {
          ListItem() { this.PostRow(post) }
        }, (post: PublicPost) => post.id)
        if (this.cursor) {
          ListItem() {
            Column({ space: 4 }) {
              if (this.appendNotice) {
                Text(this.appendNotice).id('threads-public-page-error').width('100%').fontSize('14fp')
                  .fontColor($r('app.color.timeline_text_body')).accessibilityLevel('yes')
              }
              Button(this.busy ? '读取中…' : (this.appendNotice ? '重试下一页' : '加载更多'))
                .id('threads-public-more').buttonStyle(ButtonStyleMode.TEXTUAL)
                .constraintSize({ minHeight: 48 }).enabled(!this.busy).onClick(() => { this.load(true); })
            }.width('100%').alignItems(HorizontalAlign.Start)
          }
        }
      }.id('threads-public-list').width('100%').height('100%').constraintSize({ maxWidth: 680 })
        .padding({ left: 18, right: 18, top: 14, bottom: 20 }).scrollBar(BarState.Auto)
    }.width('100%').height('100%').backgroundColor($r('app.color.timeline_surface'))
  }
}
