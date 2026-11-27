import { DiscoveryAuthor } from './DiscoveryPane';

const EMPTY_AUTHOR: DiscoveryAuthor = { id: '', name: '', handle: '', avatarColor: '', followed: false, postCount: 0 };

@Component
export struct AuthorPane {
  @Prop author: DiscoveryAuthor = EMPTY_AUTHOR;
  @BuilderParam posts: () => void;
  onBack: () => void = (): void => {};
  onFollow: () => void = (): void => {};

  @Builder
  Heading() {
    Row({ space: 8 }) {
      Button('返回', { type: ButtonType.Capsule }).id('author-back')
        .constraintSize({ minWidth: 48, minHeight: 48 }).buttonStyle(ButtonStyleMode.TEXTUAL)
        .padding({ left: 0, right: 8 }).fontSize(15).fontColor($r('app.color.timeline_text_body'))
        .onClick(() => this.onBack())
      Text('作者主页').fontSize(19).fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
        .layoutWeight(1)
    }.width('100%').padding({ top: 2, bottom: 2 })
  }

  @Builder
  Profile() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text(this.author.name).fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
            .wordBreak(WordBreak.BREAK_WORD)
          Text(this.author.handle).fontSize(15).fontColor($r('app.color.timeline_text_secondary'))
            .wordBreak(WordBreak.BREAK_WORD)
          Text('本机作者资料 · 关注仅在此设备生效').fontSize(13).fontColor($r('app.color.timeline_text_secondary'))
            .wordBreak(WordBreak.BREAK_WORD)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(this.author.name.substring(0, 1)).width(56).height(56).borderRadius(28).fontSize('24vp')
          .fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
          .fontColor($r('app.color.timeline_on_avatar')).backgroundColor(this.author.avatarColor).accessibilityLevel('no')
      }.width('100%')
      Button(this.author.followed ? '已关注' : '关注', { type: ButtonType.Capsule }).id('author-follow')
        .constraintSize({ minWidth: 96, minHeight: 48 }).padding({ left: 16, right: 16 }).fontSize(15)
        .fontColor(this.author.followed ? $r('app.color.timeline_text_body') : $r('app.color.timeline_on_action'))
        .backgroundColor(this.author.followed ? $r('app.color.timeline_toolbar_button') : $r('app.color.timeline_action'))
        .accessibilityText((this.author.followed ? '取消本机关注 ' : '在本机关注 ') + this.author.name)
        .accessibilitySelected(this.author.followed).onClick(() => this.onFollow())
      Divider().strokeWidth(0.5).color($r('app.color.timeline_border'))
      Text(`帖子 · ${this.author.postCount}`).fontSize(17).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.timeline_text_primary'))
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 18, bottom: 4 })
  }

  build() {
    Column() {
      Column() {
        this.Heading()
        Divider().strokeWidth(0.5).color($r('app.color.timeline_border'))
        List({ space: 8 }) {
          if (this.author.id.length === 0) {
            ListItem() {
              Text('无法显示作者资料。').width('100%').fontSize(15).fontColor($r('app.color.timeline_text_secondary'))
                .padding({ top: 16, bottom: 16 })
            }
          } else {
            ListItem() { this.Profile() }
            if (this.author.postCount === 0) {
              ListItem() {
                Text('这位作者还没有可显示的帖子。').width('100%').fontSize(15)
                  .fontColor($r('app.color.timeline_text_secondary')).padding({ bottom: 16 })
              }
            } else {
              this.posts()
            }
          }
        }.id('author-posts').width('100%').layoutWeight(1).scrollBar(BarState.Auto).padding({ bottom: 16 })
      }.width('100%').height('100%').constraintSize({ maxWidth: 640 }).padding({ left: 18, right: 18 })
    }.width('100%').height('100%').backgroundColor($r('app.color.timeline_surface'))
  }
}
