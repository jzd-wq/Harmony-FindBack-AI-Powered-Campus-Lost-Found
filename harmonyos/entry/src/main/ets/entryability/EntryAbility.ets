import { UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LocalAppService } from '../data/LocalAppService';

export default class EntryAbility extends UIAbility {
  onWindowStageCreate(windowStage: window.WindowStage): void {
    void LocalAppService.initialize(this.context);
    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        hilog.error(0x0000, 'Shiguang', 'loadContent failed: %{public}d', error.code);
      }
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, 'Shiguang', 'window stage destroyed');
  }

  onForeground(): void {
    void LocalAppService.initialize(this.context);
  }

  onBackground(): void {}
}
