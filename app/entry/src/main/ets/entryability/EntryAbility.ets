import { Configuration, UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onConfigurationUpdate(config: Configuration): void {
    AppStorage.setOrCreate('timelineFontScale', config.fontSizeScale ?? this.context.config.fontSizeScale ?? 1);
  }

  onForeground(): void {
    AppStorage.setOrCreate('timelineAppForeground', true);
  }

  onBackground(): void {
    AppStorage.setOrCreate('timelineAppForeground', false);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.onConfigurationUpdate(this.context.config);
    windowStage.loadContent('pages/Timeline');
  }
}