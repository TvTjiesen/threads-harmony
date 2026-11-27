@Component
export struct SettingsPane {
  @Prop reduceMotion: boolean = false;
  @Prop systemReducesMotion: boolean = false;
  @Prop motionPreferenceReady: boolean = false;
  @Prop motionPreferenceSaving: boolean = false;
  @Prop openingWeb: boolean = false;
  @Prop motionPreferenceWarning: string = '';
  onClose: () => void = () => {};
  onMotionChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onWeb: () => void = () => {};

  @Builder
  SectionTitle(title: string) {
    Text(title).width('100%').fontSize('19fp').fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.timeline_text_primary')).textAlign(TextAlign.Start)
  }

  @Builder
  SettingNote(title: string, description: string) {
    Column({ space: 4 }) {
      Text(title).width('100%').fontSize('16fp').fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.timeline_text_primary')).textAlign(TextAlign.Start)
      Text(description).width('100%').fontSize('14fp')
        .fontColor($r('app.color.timeline_text_secondary')).textAlign(TextAlign.Start)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  Appearance() {
    Column({ space: 14 }) {
      this.SectionTitle('外观')
      this.SettingNote('主题与字号', '深浅色和字号跟随系统。可在系统设置中更改。')
      Divider().color($r('app.color.timeline_border'))
      Column({ space: 6 }) {
        Row({ space: 12 }) {
          Text('减少动效').layoutWeight(1).fontSize('16fp').fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.timeline_text_primary')).textAlign(TextAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.reduceMotion })
            .id('settings-reduce-motion-toggle')
            .accessibilityText('减少动效')
            .enabled(this.motionPreferenceReady && !this.motionPreferenceSaving)
            .onChange((enabled: boolean) => { this.onMotionChange(enabled); })
        }.width('100%').constraintSize({ minHeight: 48 })
        Text(this.systemReducesMotion
          ? '系统已开启减少动效，不受此开关影响，应用不会播放点赞弹跳和详情转场。'
          : '系统未开启减少动效。打开此开关后，应用不会播放点赞弹跳和详情转场。')
          .width('100%').fontSize('14fp').fontColor($r('app.color.timeline_text_secondary')).textAlign(TextAlign.Start)
        if (!this.motionPreferenceReady) {
          Text('正在读取本机偏好…').fontSize('14fp').fontColor($r('app.color.timeline_text_secondary'))
        } else if (this.motionPreferenceSaving) {
          Text('正在写入本机偏好…').fontSize('14fp').fontColor($r('app.color.timeline_text_secondary'))
        } else if (this.motionPreferenceWarning.length > 0) {
          Text(this.motionPreferenceWarning).fontSize('14fp').fontColor($r('app.color.timeline_text_primary'))
        } else {
          Text('更改后自动保存到本机。').fontSize('14fp').fontColor($r('app.color.timeline_text_secondary'))
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').padding(16).alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.timeline_surface')).borderRadius(22)
      .border({ width: 1, color: $r('app.color.timeline_border') })
  }

  @Builder
  Account() {
    Column({ space: 14 }) {
      this.SectionTitle('账号')
      this.SettingNote('Threads 账号', '原生界面是本地演示。登录和使用真实的 Threads 账号，请前往网页。')
      Button({ type: ButtonType.Capsule }) {
        Text(this.openingWeb ? '正在打开网页…' : '打开 Threads 网页')
          .fontSize('15fp').fontColor($r('app.color.timeline_on_action')).textAlign(TextAlign.Center)
      }.id('settings-open-web-button').accessibilityText(this.openingWeb ? '正在打开网页' : '打开 Threads 网页')
        .width('100%').constraintSize({ minHeight: 48 }).padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.timeline_action'))
        .enabled(!this.openingWeb).onClick(() => { this.onWeb(); })
    }.width('100%').padding(16).alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.timeline_surface')).borderRadius(22)
      .border({ width: 1, color: $r('app.color.timeline_border') })
  }

  @Builder
  LocalData() {
    Column({ space: 14 }) {
      this.SectionTitle('本机数据')
      this.SettingNote('帖子、收藏和草稿', '本机帖子、收藏和已保存的草稿只留在这台设备，不会发布或同步到 Threads。')
      Divider().color($r('app.color.timeline_border'))
      this.SettingNote('本地回复', '在原生界面添加的回复仅在本次运行期间保留，不会发送到 Threads。')
    }.width('100%').padding(16).alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.timeline_surface')).borderRadius(22)
      .border({ width: 1, color: $r('app.color.timeline_border') })
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Button('返回', { type: ButtonType.Capsule })
          .id('settings-back-button')
          .constraintSize({ minHeight: 48 }).padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .fontSize('15fp').backgroundColor($r('app.color.timeline_toolbar_button'))
          .fontColor($r('app.color.timeline_text_body')).onClick(() => { this.onClose(); })
        Text('设置').width('100%').fontSize('28fp').fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.timeline_text_primary')).textAlign(TextAlign.Start)
        this.Appearance()
        this.Account()
        this.LocalData()
      }.width('100%').constraintSize({ maxWidth: 600 }).alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 16, bottom: 24 })
    }.id('settings-pane').width('100%').height('100%').align(Alignment.Top)
      .scrollBar(BarState.Auto).backgroundColor($r('app.color.timeline_background'))
  }
}
