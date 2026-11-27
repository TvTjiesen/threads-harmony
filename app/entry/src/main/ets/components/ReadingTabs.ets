import { SymbolGlyphModifier } from '@kit.ArkUI';
import { ExtendBarMode, HdsBarLayoutMode, HdsBarStyle, HdsTabs, hdsMaterial } from '@kit.UIDesignKit';

const RAIL_WIDTH = 96;
const BAR_MARGIN = 8;

function tabItem(id: string, label: string, icon: Resource, selectedIcon: Resource): BottomTabBarStyle {
  const normal = new SymbolGlyphModifier(icon);
  normal.fontColor([$r('app.color.timeline_text_secondary')]);
  const selected = new SymbolGlyphModifier(selectedIcon);
  selected.fontColor([$r('app.color.timeline_text_primary')]).fontWeight(FontWeight.Bold);
  const symbol: TabBarSymbol = { normal: normal, selected: selected };
  return BottomTabBarStyle.of(symbol, label).id(id).labelStyle({
    selectedColor: $r('app.color.timeline_text_primary'), unselectedColor: $r('app.color.timeline_text_secondary')
  });
}

@Component
export struct ReadingTabs {
  @Prop activeIndex: number = 0;
  @Prop wide: boolean = false;
  @BuilderParam home: () => void;
  @BuilderParam search: () => void;
  @BuilderParam activity: () => void;
  @BuilderParam profile: () => void;
  onSelectTab: (index: number) => void = (_index: number): void => {};
  onCompose: () => void = (): void => {};
  @StorageProp('timelineFontScale') private fontScale: number = 1;

  private barSize(): number {
    return this.fontScale >= 1.4 ? 72 : 56;
  }

  private contentInset(): number {
    return this.wide ? 0 : this.barSize() + BAR_MARGIN * 2;
  }

  @Builder
  ComposeAction() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.square_and_pencil')).fontSize('23vp')
        .fontColor([$r('app.color.timeline_text_primary')]).accessibilityLevel('no')
    }
    .id('nav-compose').width(48).height(48).padding(0)
    .backgroundColor(Color.Transparent).accessibilityText('发帖').onClick(() => this.onCompose())
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      HdsTabs({ index: this.activeIndex }) {
        TabContent() {
          Column() { this.home() }.width('100%').height('100%').padding({ bottom: this.contentInset() })
        }.tabBar(tabItem('nav-home', '首页', $r('sys.symbol.house'), $r('sys.symbol.house_fill')))
        TabContent() {
          Column() { this.search() }.width('100%').height('100%').padding({ bottom: this.contentInset() })
        }.tabBar(tabItem('nav-search', '搜索', $r('sys.symbol.magnifyingglass'), $r('sys.symbol.magnifyingglass')))
        TabContent() {
          Column() { this.activity() }.width('100%').height('100%').padding({ bottom: this.contentInset() })
        }.tabBar(tabItem('nav-activity', '动态', $r('sys.symbol.heart'), $r('sys.symbol.heart_fill')))
        TabContent() {
          Column() { this.profile() }.width('100%').height('100%').padding({ bottom: this.contentInset() })
        }.tabBar(tabItem('nav-profile', '我的', $r('sys.symbol.person'), $r('sys.symbol.person_fill')))
      }
      .id(this.wide ? 'side-navigation' : 'bottom-navigation')
      .width('100%').height('100%').vertical(this.wide)
      .barPosition(this.wide ? BarPosition.Start : BarPosition.End)
      .barMode(this.wide ? ExtendBarMode.HALF_SCREEN_FIXED : BarMode.Fixed)
      .barHeight(this.wide ? '100%' : this.barSize())
      .barOverlap(!this.wide)
      .barFloatingStyle(this.wide ? undefined : {
        barWidth: { smallWidth: 232, mediumWidth: 296, largeWidth: 328 },
        barSideMargin: 12,
        barBottomMargin: BAR_MARGIN,
        systemMaterialEffect: { materialType: hdsMaterial.MaterialType.ADAPTIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
        thermoCtrl: true,
        miniBar: {
          miniBarBuilder: () => this.ComposeAction(),
          miniBarStyle: HdsBarStyle.COLLAPSE,
          miniBarWidth: { smallWidth: 56, mediumWidth: 56, largeWidth: 56 },
          barLayoutMode: HdsBarLayoutMode.HORIZONTAL
        }
      })
      .scrollable(false).animationDuration(0).cachedMaxCount(3, TabsCacheMode.CACHE_LATEST_SWITCHED)
      .onChange((index: number) => {
        if (index !== this.activeIndex) {
          this.onSelectTab(index);
        }
      })
      if (this.wide) {
        Row() { this.ComposeAction() }
          .width(RAIL_WIDTH).justifyContent(FlexAlign.Center).margin({ bottom: BAR_MARGIN })
      }
    }.width('100%').height('100%')
  }
}
