import { LengthMetrics } from '@kit.ArkUI';

export interface ActivityEntry {
  id: string;
  author: string;
  body: string;
  kind: string;
  postId?: string;
}

@Component
export struct ActivityPane {
  @Prop entries: ActivityEntry[] = [];
  onOpen: (entry: ActivityEntry) => void = (_entry: ActivityEntry): void => {};
  @State private filter: string = 'all';

  private visibleEntries(): ActivityEntry[] {
    return this.entries.filter((entry: ActivityEntry) => {
      const localKind = entry.kind === 'like' || entry.kind === 'save' || entry.kind === 'reply';
      return localKind && (this.filter === 'all' || entry.kind === this.filter);
    });
  }

  private kindLabel(kind: string): string {
    if (kind === 'like') {
      return '点赞';
    }
    if (kind === 'save') {
      return '收藏';
    }
    return '回复';
  }

  private emptyMessage(): string {
    if (this.filter === 'all') {
      return '还没有本机动态。你在此设备上的点赞、收藏和回复会显示在这里。';
    }
    return `还没有本机${this.kindLabel(this.filter)}记录。`;
  }

  @Builder
  FilterButton(kind: string, label: string) {
    Button(label, { type: ButtonType.Capsule })
      .constraintSize({ minWidth: 48, minHeight: 48 })
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .fontSize(14)
      .fontColor(this.filter === kind ? $r('app.color.timeline_on_action') : $r('app.color.timeline_text_body'))
      .backgroundColor(this.filter === kind ? $r('app.color.timeline_action') : $r('app.color.timeline_toolbar_button'))
      .accessibilitySelected(this.filter === kind)
      .onClick(() => { this.filter = kind; })
  }

  @Builder
  ActivityCard(entry: ActivityEntry) {
    Column({ space: 8 }) {
      Text(`本机${this.kindLabel(entry.kind)}`)
        .fontSize(13)
        .fontColor($r('app.color.timeline_text_secondary'))
      Text(entry.author)
        .width('100%')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.timeline_text_primary'))
        .wordBreak(WordBreak.BREAK_WORD)
      Text(entry.body)
        .width('100%')
        .fontSize(15)
        .fontColor($r('app.color.timeline_text_body'))
        .wordBreak(WordBreak.BREAK_WORD)
      Button({ type: ButtonType.Normal }) {
        Text('查看帖子详情')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.timeline_text_primary'))
      }
      .id('activity-entry-' + entry.id).constraintSize({ minWidth: 48, minHeight: 48, maxWidth: '100%' })
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .borderRadius(16)
      .backgroundColor($r('app.color.timeline_toolbar_button'))
      .accessibilityText(`查看${entry.author}的帖子详情`)
      .onClick(() => { this.onOpen(entry); })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .borderRadius(20)
    .backgroundColor($r('app.color.timeline_surface'))
  }

  build() {
    Column() {
      List({ space: 12 }) {
        ListItem() {
          Column({ space: 12 }) {
            Text('动态')
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.timeline_text_primary'))
            Text('真实 Threads 账号动态尚未接入。这里只显示此设备上的互动记录，不显示账号通知。')
              .fontSize(14)
              .fontColor($r('app.color.timeline_text_secondary'))
            Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
              this.FilterButton('all', '全部')
              this.FilterButton('like', '点赞')
              this.FilterButton('save', '收藏')
              this.FilterButton('reply', '回复')
            }.width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ top: 18, bottom: 4 })
        }
        if (this.visibleEntries().length === 0) {
          ListItem() {
            Text(this.emptyMessage())
              .width('100%')
              .fontSize(15)
              .fontColor($r('app.color.timeline_text_secondary'))
              .padding(16)
              .borderRadius(20)
              .backgroundColor($r('app.color.timeline_surface'))
          }
        } else {
          ForEach(this.visibleEntries(), (entry: ActivityEntry) => {
            ListItem() { this.ActivityCard(entry) }
          }, (entry: ActivityEntry) => entry.id)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .constraintSize({ maxWidth: 640 })
      .padding({ left: 18, right: 18, bottom: 20 })
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.timeline_background'))
  }
}
