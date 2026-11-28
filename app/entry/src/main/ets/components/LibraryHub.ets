import { LengthMetrics, SegmentButtonV2Items, TabSegmentButtonV2 } from '@kit.ArkUI';
import {
  emptyIdentity, IDENTITY_BIO_LIMIT, IDENTITY_NAME_LIMIT, identityLength, LocalIdentity, normalizeIdentity
} from '../model/LocalIdentity';

const PROFILE_MAX_WIDTH = 640;

@Component
export struct LibraryHub {
  @Prop identity: LocalIdentity = emptyIdentity();
  @Prop mode: number = 0;
  @Prop mediaMode: number = 0;
  private readonly mediaFilters: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '全部' }, { text: '图片' }, { text: '视频' }
  ]);
  onMediaMode: (value: number) => void = (_value: number): void => {};
  @Prop hasItems: boolean = false;
  @Prop busy: boolean = false;
  @Prop message: string = '';
  @BuilderParam items: () => void;
  onMode: (value: number) => void = (_value: number): void => {};
  onEdit: () => void = (): void => {};
  onCompose: () => void = (): void => {};
  onSettings: () => void = (): void => {};
  onWeb: () => void = (): void => {};
  onBrowse?: () => void;
  onRetryRead?: () => void;

  private emptyTitle(): string {
    switch (this.mode) {
      case 1: return '还没有收藏';
      case 2: return '还没有点赞';
      case 3: return '还没有回复';
      default: return this.mediaMode === 1 ? '还没有图片帖' : this.mediaMode === 2 ? '还没有视频帖' : '还没有本机帖子';
    }
  }

  private emptyDetail(): string {
    switch (this.mode) {
      case 1: return '点按帖子下方的收藏按钮，就能在这里找到它。';
      case 2: return '点按帖子下方的点赞按钮，就能在这里找到它。';
      case 3: return '打开帖子并写下回复，你的本机回复就会出现在这里。';
      default: return this.mediaMode === 0 ? '写一条草稿，预览后可将它加入本机时间线。' :
        '切回「全部」可以查看其他本机帖子。';
    }
  }

  private managementDetail(): string {
    switch (this.mode) {
      case 1: return '再次点按帖子的收藏按钮可取消收藏。';
      case 2: return '再次点按帖子的点赞按钮可取消点赞。';
      case 3: return '点按回复查看原帖，或用「删除回复」移除本机回复。';
      default: return '可从「帖子操作」编辑；打开详情可删除本机帖子。';
    }
  }

  @Builder
  Profile() {
    Column({ space: 10 }) {
      Text('我的').fontSize('15fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.timeline_text_secondary'))
      Row({ space: 16 }) {
        Column({ space: 3 }) {
          Text(this.identity.name).id('library-identity-name').width('100%').fontSize('30fp')
            .fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary')).wordBreak(WordBreak.BREAK_WORD)
          Text('本机资料').fontSize('14fp').fontColor($r('app.color.timeline_text_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Stack() {
          SymbolGlyph($r('sys.symbol.person_fill')).fontSize('28vp')
            .fontColor([$r('app.color.timeline_on_action')]).accessibilityLevel('no')
        }.width(56).height(56).borderRadius(28).backgroundColor($r('app.color.timeline_action'))
          .accessibilityLevel('no')
      }.width('100%').alignItems(VerticalAlign.Top)
      Text(this.identity.bio.length > 0 ? this.identity.bio : '还没有简介，可在「编辑资料」添加')
        .id('library-identity-bio').width('100%').fontSize('16fp').wordBreak(WordBreak.BREAK_WORD)
        .fontColor(this.identity.bio.length > 0 ? $r('app.color.timeline_text_body') : $r('app.color.timeline_text_secondary'))
      Text('只保存在这台设备，不会同步到 Threads 账号。').width('100%').fontSize('13fp')
        .fontColor($r('app.color.timeline_text_secondary'))
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        Button('编辑资料', { type: ButtonType.Normal })
          .id('library-edit').flexGrow(1).constraintSize({ minHeight: 48 })
          .padding({ left: 14, right: 14, top: 8, bottom: 8 }).borderRadius(10)
          .fontSize('15fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.timeline_text_primary'))
          .backgroundColor(Color.Transparent).border({ width: 1, color: $r('app.color.timeline_text_secondary') })
          .enabled(!this.busy).onClick(() => this.onEdit())
        Button('写帖草稿', { type: ButtonType.Normal })
          .id('library-compose').flexGrow(1).constraintSize({ minHeight: 48 })
          .padding({ left: 14, right: 14, top: 8, bottom: 8 }).borderRadius(10)
          .fontSize('15fp').fontWeight(FontWeight.Medium).fontColor($r('app.color.timeline_on_action'))
          .backgroundColor($r('app.color.timeline_action')).enabled(!this.busy).onClick(() => this.onCompose())
      }.width('100%').margin({ top: 4 })
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(4) } }) {
        Button('设置', { type: ButtonType.Normal }).id('library-settings').buttonStyle(ButtonStyleMode.TEXTUAL)
          .constraintSize({ minWidth: 48, minHeight: 48 }).padding({ left: 8, right: 8, top: 8, bottom: 8 })
          .fontSize('14fp').fontColor($r('app.color.timeline_text_body')).onClick(() => this.onSettings())
        Button('打开 Threads 网页', { type: ButtonType.Normal }).id('library-web').buttonStyle(ButtonStyleMode.TEXTUAL)
          .constraintSize({ minWidth: 48, minHeight: 48 }).padding({ left: 8, right: 8, top: 8, bottom: 8 })
          .fontSize('14fp').fontColor($r('app.color.timeline_text_body')).onClick(() => this.onWeb())
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  ModeButton(value: number, label: string) {
    Button({ type: ButtonType.Normal }) {
      Column() {
        Text(label).width('100%').textAlign(TextAlign.Center).constraintSize({ minHeight: 46 })
          .padding({ top: 8, bottom: 8 }).fontSize('15fp')
          .fontWeight(this.mode === value ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.mode === value ? $r('app.color.timeline_text_primary') : $r('app.color.timeline_text_secondary'))
          .accessibilityLevel('no')
        Divider().strokeWidth(2)
          .color(this.mode === value ? $r('app.color.timeline_action') : $r('app.color.timeline_border'))
      }.width('100%')
    }.id(`library-mode-${value}`).layoutWeight(1).constraintSize({ minWidth: 48, minHeight: 48 })
      .padding(0).borderRadius(0).backgroundColor(Color.Transparent)
      .accessibilityText(label).accessibilitySelected(this.mode === value)
      .onClick(() => this.onMode(value))
  }

  @Builder
  Status() {
    if (this.busy || this.message.length > 0 || this.onRetryRead !== undefined) {
      Column({ space: 6 }) {
        Text(this.busy ? '正在处理本机内容…' : this.message || '暂时无法读取本机内容。')
          .id('library-status').width('100%').fontSize('14fp')
          .fontColor($r('app.color.timeline_text_primary')).accessibilityLevel('yes')
        if (!this.busy && this.onRetryRead !== undefined) {
          Button('重试读取').id('library-retry-read').buttonStyle(ButtonStyleMode.TEXTUAL)
            .constraintSize({ minHeight: 48 }).fontColor($r('app.color.timeline_text_primary'))
            .onClick(() => { this.onRetryRead?.(); })
        }
      }.width('100%').alignItems(HorizontalAlign.Start).padding(12).borderRadius(12)
        .backgroundColor($r('app.color.timeline_surface_muted'))
    }
  }

  @Builder
  EmptyLibrary() {
    Column({ space: 6 }) {
      Text(this.emptyTitle()).width('100%').fontSize('17fp').fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.timeline_text_primary'))
      Text(this.emptyDetail()).width('100%').fontSize('14fp').fontColor($r('app.color.timeline_text_secondary'))
      if (this.mode === 0 && this.mediaMode !== 0) {
        Button('查看全部帖子').id('library-empty-all-posts').buttonStyle(ButtonStyleMode.TEXTUAL)
          .constraintSize({ minHeight: 48 }).fontColor($r('app.color.timeline_text_primary'))
          .onClick(() => { this.onMediaMode(0); })
      } else if (this.mode === 0) {
        Button('写帖草稿').id('library-empty-compose').buttonStyle(ButtonStyleMode.TEXTUAL)
          .constraintSize({ minHeight: 48 }).fontColor($r('app.color.timeline_text_primary'))
          .onClick(() => this.onCompose())
      } else if (this.onBrowse !== undefined) {
        Button('去首页看看').id('library-empty-browse').buttonStyle(ButtonStyleMode.TEXTUAL)
          .constraintSize({ minHeight: 48 }).fontColor($r('app.color.timeline_text_primary'))
          .onClick(() => { this.onBrowse?.(); })
      }
    }.id('library-empty').width('100%').alignItems(HorizontalAlign.Start).padding({ top: 12, bottom: 16 })
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        this.Profile()
        Row() {
          this.ModeButton(0, '帖子')
          this.ModeButton(1, '收藏')
          this.ModeButton(2, '点赞')
          this.ModeButton(3, '回复')
        }.width('100%')
        if (this.mode === 0) {
          TabSegmentButtonV2({ items: this.mediaFilters, itemMaxFontScale: 2, selectedIndex: this.mediaMode,
            itemMinHeight: LengthMetrics.vp(48), $selectedIndex: (value: number) => this.onMediaMode(value) })
            .id('library-media-filter').width('100%').constraintSize({ maxWidth: 388 })
        }
        this.Status()
        if (this.hasItems) {
          Column({ space: 10 }) {
            Text(this.managementDetail()).width('100%').fontSize('14fp').fontColor($r('app.color.timeline_text_secondary'))
            this.items()
          }.width('100%').alignItems(HorizontalAlign.Start)
        } else if (!this.busy && this.onRetryRead === undefined) {
          this.EmptyLibrary()
        }
      }.width('100%').constraintSize({ maxWidth: PROFILE_MAX_WIDTH }).alignItems(HorizontalAlign.Start)
        .padding({ left: 18, right: 18, top: 20, bottom: 24 })
    }.id('library-hub').width('100%').height('100%').align(Alignment.Top)
      .scrollBar(BarState.Auto).backgroundColor($r('app.color.timeline_background'))
  }
}

@Component
export struct IdentityEditor {
  @Prop name: string = '';
  @Prop bio: string = '';
  @Prop busy: boolean = false;
  @Prop message: string = '';
  onName: (value: string) => void = (_value: string): void => {};
  onBio: (value: string) => void = (_value: string): void => {};
  onSave: () => void = (): void => {};
  onBack: () => void = (): void => {};

  private fieldCount(value: string, limit: number): string {
    const count = identityLength(value);
    return count < 0 ? `最多 ${limit} 个字符` : `${count} / ${limit}`;
  }

  private nameError(): string {
    const name = this.name.trim();
    if (name.length === 0) { return '请输入名称。'; }
    if (identityLength(name) > IDENTITY_NAME_LIMIT) { return `名称最多 ${IDENTITY_NAME_LIMIT} 个字符。`; }
    return normalizeIdentity(name, '') === undefined ? '名称必须是单行，不能包含无效字符。' : '';
  }

  private cleanBio(): string {
    return this.bio.replace(/\r\n?|[\u2028\u2029]/g, '\n').trim();
  }

  private bioError(): string {
    const bio = this.cleanBio();
    if (identityLength(bio) > IDENTITY_BIO_LIMIT) { return `简介最多 ${IDENTITY_BIO_LIMIT} 个字符。`; }
    return normalizeIdentity('你', bio) === undefined ? '简介中包含无效字符。' : '';
  }

  private focusBio(event: SubmitEvent): void {
    if (this.busy) { return; }
    if (this.nameError().length > 0) {
      event.keepEditableState();
      return;
    }
    try {
      this.getUIContext().getFocusController().requestFocus('identity-bio-input');
    } catch (_error) {
      // The editor may already be leaving the destination.
    }
  }

  @Builder
  FieldLabel(label: string) {
    Text(label).width('100%').fontSize('16fp').fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.timeline_text_primary'))
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Button('返回', { type: ButtonType.Capsule }).id('identity-back').accessibilityText('返回个人主页')
          .constraintSize({ minWidth: 48, minHeight: 48 }).padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .fontSize('15fp').fontColor($r('app.color.timeline_text_body'))
          .backgroundColor($r('app.color.timeline_toolbar_button')).enabled(!this.busy).onClick(() => this.onBack())
        Column({ space: 5 }) {
          Text('编辑资料').width('100%').fontSize('28fp').fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.timeline_text_primary'))
          Text('这里编辑的是本机资料，不会更改你的 Threads 账号。').width('100%').fontSize('14fp')
            .fontColor($r('app.color.timeline_text_secondary'))
        }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 6 }) {
          this.FieldLabel('名称（必填）')
          TextInput({ text: this.name, placeholder: '在本机显示的名称' }).id('identity-name-input')
            .width('100%').constraintSize({ minHeight: 52 }).fontSize('16fp')
            .padding({ left: 14, right: 14, top: 10, bottom: 10 }).borderRadius(12)
            .fontColor($r('app.color.timeline_text_primary')).placeholderColor($r('app.color.timeline_text_secondary'))
            .caretColor($r('app.color.timeline_text_primary')).backgroundColor($r('app.color.timeline_surface_muted'))
            .accessibilityText('名称，必填').accessibilityDescription(this.nameError() || `最多 ${IDENTITY_NAME_LIMIT} 个字符`)
            .enterKeyType(EnterKeyType.Next).onSubmit((_key: EnterKeyType, event: SubmitEvent) => { this.focusBio(event); })
            .enabled(!this.busy).onChange((value: string) => this.onName(value))
          Text(this.fieldCount(this.name.trim(), IDENTITY_NAME_LIMIT)).width('100%').fontSize('13fp')
            .fontColor($r('app.color.timeline_text_secondary'))
          if (this.nameError().length > 0) {
            Text(this.nameError()).id('identity-validation').width('100%').fontSize('14fp')
              .fontColor($r('app.color.timeline_text_primary')).accessibilityLevel('yes')
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 6 }) {
          this.FieldLabel('简介（选填）')
          TextArea({ text: this.bio, placeholder: '写一段简单的自我介绍' }).id('identity-bio-input')
            .width('100%').constraintSize({ minHeight: 116, maxHeight: 260 }).fontSize('16fp')
            .padding({ left: 14, right: 14, top: 10, bottom: 10 }).borderRadius(12)
            .fontColor($r('app.color.timeline_text_primary')).placeholderColor($r('app.color.timeline_text_secondary'))
            .caretColor($r('app.color.timeline_text_primary')).backgroundColor($r('app.color.timeline_surface_muted'))
            .accessibilityText('简介，选填').accessibilityDescription(this.bioError() || `最多 ${IDENTITY_BIO_LIMIT} 个字符`)
            .enabled(!this.busy).onChange((value: string) => this.onBio(value))
          Text(this.fieldCount(this.cleanBio(), IDENTITY_BIO_LIMIT)).width('100%').fontSize('13fp')
            .fontColor($r('app.color.timeline_text_secondary'))
          if (this.bioError().length > 0) {
            Text(this.bioError()).id(this.nameError().length === 0 ? 'identity-validation' : 'identity-bio-validation')
              .width('100%').fontSize('14fp').fontColor($r('app.color.timeline_text_primary')).accessibilityLevel('yes')
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
        if (this.busy || this.message.length > 0) {
          Text(this.busy ? '正在保存本机资料…' : this.message).id('identity-status').width('100%').fontSize('14fp')
            .fontColor($r('app.color.timeline_text_primary')).accessibilityLevel('yes')
            .padding(12).borderRadius(12).backgroundColor($r('app.color.timeline_surface_muted'))
        }
        Button(this.busy ? '正在保存…' : this.message.length > 0 ? '重试保存' : '保存到本机',
          { type: ButtonType.Normal }).id('identity-save')
          .width('100%').constraintSize({ minHeight: 48 }).padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .borderRadius(10).fontSize('16fp').fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.timeline_on_action')).backgroundColor($r('app.color.timeline_action'))
          .enabled(!this.busy && normalizeIdentity(this.name, this.bio) !== undefined).onClick(() => this.onSave())
      }.width('100%').constraintSize({ maxWidth: PROFILE_MAX_WIDTH }).alignItems(HorizontalAlign.Start)
        .padding({ left: 18, right: 18, top: 16, bottom: 24 })
    }.id('identity-editor').width('100%').height('100%').align(Alignment.Top)
      .scrollBar(BarState.Auto).backgroundColor($r('app.color.timeline_background'))
  }
}
