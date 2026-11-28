import { FrameCallback, KeyboardAvoidMode, LengthMetrics } from '@kit.ArkUI';

export interface ConversationReply {
  id: string;
  postId: string;
  author: string;
  body: string;
  local: boolean;
  parentId?: string;
  toAuthor?: string;
}

const REPLY_LIMIT = 280;
// The original post and discussion heading share the first ListItem.
const FIRST_REPLY_INDEX = 1;

class ConversationFrame extends FrameCallback {
  private readonly action: () => void;

  constructor(action: () => void) {
    super();
    this.action = action;
  }

  onIdle(_timeLeftInNano: number): void {
    this.action();
  }
}

@Component
export struct ConversationPane {
  @BuilderParam rootPost: () => void;
  @Prop @Watch('scheduleTarget') rows: ConversationReply[] = [];
  @Prop @Watch('targetChanged') focusId: string = '';
  @Prop rootAuthor: string = '';
  @Prop recipient: string = '';
  @Prop contextLine: string = '';
  @Prop @Watch('syncKeyboardMode') expanded: boolean = false;
  @Prop draft: string = '';
  @Prop @Watch('syncKeyboardMode') confirmLeave: boolean = false;
  @Prop largeText: boolean = false;
  @Prop busy: boolean = false;
  @State private paneWidth: number = 0;
  onBack: () => void = (): void => {};
  onEdit: (id: string) => void = (_id: string): void => {};
  onExpand: () => void = (): void => {};
  onDraft: (s: string) => void = (_s: string): void => {};
  onSend: () => void = (): void => {};
  onDiscard: () => void = (): void => {};
  onKeep: () => void = (): void => {};

  private readonly listScroller: Scroller = new Scroller();
  private listMounted: boolean = false;
  private active: boolean = false;
  private scrollPending: boolean = false;
  private scrolledId: string = '';
  private savedKeyboardMode: KeyboardAvoidMode | undefined = undefined;

  aboutToAppear(): void {
    this.active = true;
    this.syncKeyboardMode();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.listMounted = false;
    this.syncKeyboardMode();
  }

  private syncKeyboardMode(): void {
    const ui = this.getUIContext();
    if (this.active && this.expanded && !this.confirmLeave) {
      if (this.savedKeyboardMode === undefined) {
        this.savedKeyboardMode = ui.getKeyboardAvoidMode();
        ui.setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
      }
    } else if (this.savedKeyboardMode !== undefined) {
      if (ui.getKeyboardAvoidMode() === KeyboardAvoidMode.RESIZE) {
        ui.setKeyboardAvoidMode(this.savedKeyboardMode);
      }
      this.savedKeyboardMode = undefined;
    }
  }

  private targetIndex(): number {
    if (this.focusId === '') {
      return -1;
    }
    const index = this.rows.findIndex((row: ConversationReply) => row.id === this.focusId);
    return index < 0 ? -1 : FIRST_REPLY_INDEX + index;
  }

  private targetChanged(): void {
    this.scrolledId = '';
    this.scheduleTarget();
  }

  private scheduleTarget(): void {
    if (!this.listMounted || this.scrollPending || this.focusId === '' || this.scrolledId === this.focusId) {
      return;
    }
    this.scrollPending = true;
    this.getUIContext().postFrameCallback(new ConversationFrame(() => {
      this.scrollPending = false;
      if (!this.active || !this.listMounted) {
        return;
      }
      // Resolve again after layout: the parent may have inserted a reply or selected another ID.
      const index = this.targetIndex();
      if (index >= FIRST_REPLY_INDEX) {
        this.listScroller.scrollToIndex(index, false, ScrollAlign.START);
        this.scrolledId = this.focusId;
      }
    }));
  }

  private focusEditor(): void {
    this.getUIContext().postFrameCallback(new ConversationFrame(() => {
      if (this.active && this.expanded && !this.confirmLeave) {
        try {
          this.getUIContext().getFocusController().requestFocus('convo-input');
        } catch (_error) {
          // A destination may have been covered between layout and focus transfer.
        }
      }
    }));
  }

  private editReply(id: string): void {
    const alreadyOpen = this.expanded;
    this.onEdit(id);
    if (alreadyOpen) {
      this.focusEditor();
    }
  }

  private recipientLabel(): string {
    return this.recipient || '原帖作者';
  }

  private replyRelation(row: ConversationReply): string {
    if (!row.toAuthor) {
      return '回复原帖';
    }
    return '回复 ' + (row.toAuthor.startsWith('@') ? row.toAuthor : '@' + row.toAuthor);
  }

  private stackReplyActions(): boolean {
    return this.largeText || (this.paneWidth > 0 && this.paneWidth < 340);
  }

  @Builder
  Heading() {
    Row({ space: 12 }) {
      Button('返回', { type: ButtonType.Capsule })
        .id('convo-back').constraintSize({ minWidth: 48, minHeight: 48 })
        .buttonStyle(ButtonStyleMode.TEXTUAL).fontSize(15).fontColor($r('app.color.timeline_text_body'))
        .padding({ left: 10, right: 10 }).accessibilityText('返回').onClick(() => this.onBack())
      Column({ space: 1 }) {
        Text('帖子详情').fontSize(19).fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
        Text(this.rootAuthor + '的讨论').fontSize(12).fontColor($r('app.color.timeline_text_secondary'))
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').padding({ top: 2, bottom: 2 })
  }

  @Builder
  DiscussionHeader() {
    Column({ space: 6 }) {
      this.rootPost()
      Button('回复原帖', { type: ButtonType.Capsule })
        .id('convo-reply-root').constraintSize({ minHeight: 48 }).buttonStyle(ButtonStyleMode.TEXTUAL)
        .fontSize(14).fontColor($r('app.color.timeline_text_body')).onClick(() => this.editReply(''))
      Divider().strokeWidth(0.5).color($r('app.color.timeline_border'))
      Text(`讨论 · ${this.rows.length} 条回复`).margin({ top: 10 }).fontSize(17).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.timeline_text_primary'))
      Text('这里显示示例与本机回复。你添加的回复仅保存在这台设备，不会发送到 Threads。').fontSize(13)
        .fontColor($r('app.color.timeline_text_secondary')).padding({ bottom: 10 })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  ReplyRow(row: ConversationReply) {
    Row({ space: this.largeText ? 8 : 12 }) {
      Column({ space: 3 }) {
        Divider().vertical(true).height(8).strokeWidth(1).color($r('app.color.timeline_border'))
        Text(row.author.substring(0, 1)).width(30).height(30).borderRadius(15).fontSize('13vp')
          .textAlign(TextAlign.Center).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.timeline_text_body')).backgroundColor($r('app.color.timeline_toolbar_button'))
        if (row.id !== this.rows[this.rows.length - 1]?.id) {
          Divider().vertical(true).height(12).strokeWidth(1).color($r('app.color.timeline_border'))
        }
      }.width(32).alignSelf(ItemAlign.Stretch).accessibilityLevel('no-hide-descendants')
      Column({ space: 4 }) {
        Column({ space: 4 }) {
          if (row.id === this.focusId) {
            Text('当前定位的回复').fontSize(13).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.timeline_text_primary'))
          }
          Text(row.author + (row.local ? ' · 本机' : '')).fontSize(16).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.timeline_text_primary')).wordBreak(WordBreak.BREAK_WORD)
          Text(this.replyRelation(row)).fontSize(13).fontColor($r('app.color.timeline_text_secondary'))
            .wordBreak(WordBreak.BREAK_WORD)
          Text(row.body).width('100%').fontSize(16).fontColor($r('app.color.timeline_text_body'))
            .wordBreak(WordBreak.BREAK_WORD).copyOption(CopyOptions.InApp)
        }.id('convo-target-' + row.id).width('100%').alignItems(HorizontalAlign.Start)
          .accessibilityGroup(true).accessibilitySelected(row.id === this.focusId)
          .accessibilityText((row.id === this.focusId ? '当前定位的回复，' : '') + row.author +
            (row.local ? '，本机回复，' : '，') + this.replyRelation(row) + '：' + row.body)
        Button('回复', { type: ButtonType.Capsule })
          .id('convo-reply-' + row.id).buttonStyle(ButtonStyleMode.TEXTUAL)
          .padding({ left: 0, right: 10 }).constraintSize({ minHeight: 48, minWidth: 48 })
          .fontSize(14).fontColor($r('app.color.timeline_text_secondary'))
          .accessibilityText('回复 ' + row.author + ' 的这条回复').onClick(() => this.editReply(row.id))
        Divider().strokeWidth(0.5).color($r('app.color.timeline_border'))
      }.layoutWeight(1).padding({ top: 10, right: 4 }).alignItems(HorizontalAlign.Start)
    }.width('100%').alignItems(VerticalAlign.Top)
      .padding({ left: row.parentId && !this.largeText ? 12 : 0 })
      .backgroundColor(row.id === this.focusId ? $r('app.color.timeline_surface_muted') : Color.Transparent)
  }

  @Builder
  CollapsedEntry() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.square_and_pencil')).fontSize('18vp')
          .fontColor([$r('app.color.timeline_text_secondary')]).accessibilityLevel('no')
        Text((this.draft.length > 0 ? '继续回复 ' : '回复 ') + this.recipientLabel() + '…')
          .fontSize(15).fontColor($r('app.color.timeline_text_body')).layoutWeight(1)
          .textAlign(TextAlign.Start).wordBreak(WordBreak.BREAK_WORD)
      }.width('100%')
    }.id('convo-compose').width('100%').constraintSize({ minHeight: 48 })
      .padding({ left: 14, right: 14, top: 8, bottom: 8 }).borderRadius(16)
      .backgroundColor($r('app.color.timeline_surface_muted')).margin({ top: 8, bottom: 8 })
      .accessibilityText('展开编辑，回复 ' + this.recipientLabel()).onClick(() => this.onExpand())
  }

  @Builder
  ReplyInput() {
    TextArea({ text: this.draft, placeholder: '写下你的回复…' })
      .id('convo-input').width('100%').constraintSize({ minHeight: 48, maxHeight: this.largeText ? 96 : 80 })
      .padding({ top: 8, right: 10, bottom: 8, left: 10 }).maxLength(REPLY_LIMIT).fontSize(16)
      .fontColor($r('app.color.timeline_text_body')).placeholderColor($r('app.color.timeline_text_muted'))
      .borderRadius(12).backgroundColor($r('app.color.timeline_surface_muted')).enableKeyboardOnFocus(true)
      .accessibilityText('本机回复内容，回复 ' + this.recipientLabel()).accessibilityDescription(this.contextLine)
      .enabled(!this.busy).onChange((value: string) => this.onDraft(value)).onAppear(() => this.focusEditor())
  }

  @Builder
  ReplySubmit() {
    Button(this.busy ? '正在保存…' : '添加', { type: ButtonType.Capsule })
      .id('convo-submit').constraintSize({ minHeight: 48 }).padding({ left: 12, right: 12 }).fontSize(15)
      .fontColor($r('app.color.timeline_on_action')).backgroundColor($r('app.color.timeline_action'))
      .accessibilityText('添加本机回复，不发送到 Threads')
      .enabled(!this.busy && this.draft.trim().length > 0 && this.draft.length <= REPLY_LIMIT)
      .onClick(() => this.onSend())
  }

  @Builder
  Editor() {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text('回复 ' + this.recipientLabel()).fontSize(15).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.timeline_text_primary')).layoutWeight(1)
          .maxLines(this.largeText ? 2 : 1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.draft.length}/${REPLY_LIMIT}`).fontSize(12).fontColor($r('app.color.timeline_text_secondary'))
      }.width('100%')
      Text('上下文：' + this.contextLine).width('100%').fontSize(13).fontColor($r('app.color.timeline_text_secondary'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.End,
        space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        Column() { this.ReplyInput() }
          .flexBasis(this.stackReplyActions() ? '100%' : '50%').flexGrow(1)
        this.ReplySubmit()
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 6, bottom: 8 })
  }

  @Builder
  LeaveDecision() {
    Column({ space: 4 }) {
      Text('放弃未发送的回复？').fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(4) } }) {
        Button('继续编辑').id('convo-keep').constraintSize({ minHeight: 48 }).fontSize(15)
          .fontColor($r('app.color.timeline_on_action')).backgroundColor($r('app.color.timeline_action'))
          .onClick(() => this.onKeep())
        Button('放弃回复').id('convo-discard').constraintSize({ minHeight: 48 }).fontSize(15)
          .fontColor($r('app.color.timeline_text_body')).backgroundColor($r('app.color.timeline_toolbar_button'))
          .onClick(() => this.onDiscard())
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 8, bottom: 8 })
  }

  build() {
    Column() {
      Column() {
        this.Heading()
        Divider().strokeWidth(0.5).color($r('app.color.timeline_border'))
        List({ scroller: this.listScroller, initialIndex: Math.max(0, this.targetIndex()) }) {
          ListItem() { this.DiscussionHeader() }
          if (this.rows.length === 0) {
            ListItem() {
              Text('还没有可显示的回复。可以在下方写下第一条本机回复。').fontSize(16).fontColor($r('app.color.timeline_text_body'))
                .width('100%').padding({ top: 20, bottom: 24 })
            }
          } else {
            ForEach(this.rows, (row: ConversationReply) => {
              ListItem() { this.ReplyRow(row) }
            }, (row: ConversationReply) => row.id)
          }
        }.id('convo-list').width('100%').layoutWeight(1).scrollBar(BarState.Auto)
          .onAppear(() => {
            this.listMounted = true;
            this.scheduleTarget();
          })
        Divider().strokeWidth(0.5).color($r('app.color.timeline_border'))
        if (this.confirmLeave) {
          Scroll() { this.LeaveDecision() }.width('100%').constraintSize({ maxHeight: '75%' })
        } else if (this.expanded) {
          Scroll() { this.Editor() }.width('100%').constraintSize({ maxHeight: '60%' })
        } else {
          this.CollapsedEntry()
        }
      }.width('100%').height('100%').constraintSize({ maxWidth: 640 }).padding({ left: 16, right: 16 })
        .onAreaChange((_previous: Area, current: Area) => {
          const width = Number(current.width);
          if (Number.isFinite(width) && width > 0 && width !== this.paneWidth) { this.paneWidth = width; }
        })
    }.width('100%').height('100%').backgroundColor($r('app.color.timeline_surface'))
  }
}
