import UserNotifications
import AppKit

/// 通知管理器
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// 请求通知权限
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("通知权限已授予")
            } else if let error = error {
                print("通知权限请求失败: \(error.localizedDescription)")
            }
        }
    }

    /// 发送上传完成通知
    func sendUploadCompleteNotification(fileName: String, imageURL: String) {
        let content = UNMutableNotificationContent()
        content.title = "Pic2Link"
        content.body = L10n.tr("notification.uploadComplete", fileName)
        content.userInfo = ["imageURL": imageURL]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("发送通知失败: \(error.localizedDescription)")
            }
        }

        playUploadSuccessSound()
    }

    /// 发送错误通知
    func sendErrorNotification(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Pic2Link"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// 发送简单通知
    func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    private func playUploadSuccessSound() {
        NSSound(named: NSSound.Name("Glass"))?.play()
    }
}
