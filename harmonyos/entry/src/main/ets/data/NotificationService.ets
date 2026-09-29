import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';

/**
 * HarmonyOS 本地通知适配器。
 * 通知属于增强体验，权限或设备不支持时不阻断主业务流程。
 */
export class NotificationService {
  private permissionRequested: boolean = false;
  private nextNotificationId: number = 1000;

  async publish(title: string, text: string, context: common.UIAbilityContext): Promise<boolean> {
    try {
      if (!this.permissionRequested) {
        this.permissionRequested = true;
        try {
          await notificationManager.requestEnableNotification(context);
        } catch (error) {
          // 用户拒绝或系统已经处理过授权时，继续尝试发布即可。
        }
      }

      await notificationManager.publish({
        id: this.nextNotificationId++,
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title,
            text
          }
        }
      });
      return true;
    } catch (error) {
      return false;
    }
  }
}
