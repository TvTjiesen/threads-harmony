import { LengthMetrics } from '@kit.ArkUI';

@Component
export struct ThreadPartPicker {
  @Prop count: number = 1;
  @Prop activeIndex: number = 0;
  @Prop maxParts: number = 6;
  @Prop editable: boolean = true;
  onSelect: (index: number) => void = (_index: number): void => {};
  onAdd: () => void = (): void => {};
  onMove: (direction: number) => void = (_direction: number): void => {};
  onRemove: () => void = (): void => {};

  private partIndices(): number[] {
    const indices: number[] = [];
    for (let index = 0; index < this.count; index++) {
      indices.push(index);
    }
    return indices;
  }

  @Builder
  PartButton(index: number) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 3 }) {
        Text(`${index + 1}`).fontSize('15fp').wordBreak(WordBreak.BREAK_WORD)
          .fontWeight(index === this.activeIndex ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(index === this.activeIndex ? $r('app.color.timeline_text_primary') : $r('app.color.timeline_text_secondary'))
          .accessibilityLevel('no')
        Divider().width(20).strokeWidth(2)
          .color(index === this.activeIndex ? $r('app.color.timeline_action') : Color.Transparent)
          .accessibilityLevel('no')
      }
    }
    .id(`thread-part-${index}`).buttonStyle(ButtonStyleMode.TEXTUAL)
    .constraintSize({ minWidth: 48, minHeight: 48, maxWidth: '100%' })
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .accessibilityText(`第 ${index + 1} 段，共 ${this.count} 段`).accessibilitySelected(index === this.activeIndex)
    .enabled(this.editable).onClick(() => this.onSelect(index))
  }

  @Builder
  PartStatus() {
    Text(`第 ${this.activeIndex + 1} 段，共 ${this.count} 段`)
      .constraintSize({ maxWidth: '100%' }).fontSize('14fp')
      .fontColor($r('app.color.timeline_text_secondary')).wordBreak(WordBreak.BREAK_WORD)
  }

  @Builder
  AddButton() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.plus')).fontSize('16vp')
          .fontColor([$r('app.color.timeline_text_body')]).accessibilityLevel('no')
        Text('添加段落').fontSize('14fp').fontColor($r('app.color.timeline_text_body'))
          .flexShrink(1).wordBreak(WordBreak.BREAK_WORD).accessibilityLevel('no')
      }
    }
    .id('thread-add-part').buttonStyle(ButtonStyleMode.TEXTUAL)
    .constraintSize({ minWidth: 48, minHeight: 48, maxWidth: '100%' })
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .accessibilityText('添加段落').enabled(this.editable && this.count < this.maxParts)
    .onClick(() => this.onAdd())
  }

  @Builder
  EditActions() {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center,
      space: { main: LengthMetrics.vp(4), cross: LengthMetrics.vp(2) } }) {
      this.PartStatus()
      Button({ type: ButtonType.Normal }) {
        Text('前移').fontSize('14fp').fontColor($r('app.color.timeline_text_body'))
          .wordBreak(WordBreak.BREAK_WORD).accessibilityLevel('no')
      }
      .id('thread-move-earlier').buttonStyle(ButtonStyleMode.TEXTUAL)
      .constraintSize({ minWidth: 48, minHeight: 48, maxWidth: '100%' }).padding({ left: 8, right: 8, top: 6, bottom: 6 })
      .accessibilityText('将当前段落前移').enabled(this.editable && this.activeIndex > 0)
      .onClick(() => this.onMove(-1))
      Button({ type: ButtonType.Normal }) {
        Text('后移').fontSize('14fp').fontColor($r('app.color.timeline_text_body'))
          .wordBreak(WordBreak.BREAK_WORD).accessibilityLevel('no')
      }
      .id('thread-move-later').buttonStyle(ButtonStyleMode.TEXTUAL)
      .constraintSize({ minWidth: 48, minHeight: 48, maxWidth: '100%' }).padding({ left: 8, right: 8, top: 6, bottom: 6 })
      .accessibilityText('将当前段落后移').enabled(this.editable && this.activeIndex < this.count - 1)
      .onClick(() => this.onMove(1))
      Button({ type: ButtonType.Normal }) {
        Text('删除').fontSize('14fp').fontColor($r('app.color.timeline_text_body'))
          .wordBreak(WordBreak.BREAK_WORD).accessibilityLevel('no')
      }
      .id('thread-remove-part').buttonStyle(ButtonStyleMode.TEXTUAL)
      .constraintSize({ minWidth: 48, minHeight: 48, maxWidth: '100%' }).padding({ left: 8, right: 8, top: 6, bottom: 6 })
      .accessibilityText('删除当前段落').enabled(this.editable).onClick(() => this.onRemove())
    }.width('100%')
  }

  build() {
    Column() {
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center,
        space: { main: LengthMetrics.vp(2), cross: LengthMetrics.vp(2) } }) {
        ForEach(this.partIndices(), (index: number) => { this.PartButton(index) }, (index: number) => `${index}`)
        this.AddButton()
        if (this.count <= 1) {
          this.PartStatus()
        }
      }.width('100%')
      if (this.count > 1) {
        this.EditActions()
      }
    }.id('thread-parts').width('100%').alignItems(HorizontalAlign.Start)
  }
}
