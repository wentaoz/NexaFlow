import AppKit
import Foundation
import UserNotifications

final class AppNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationService()

    private override init() {
        super.init()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func authorizationDescription(completion: @escaping (String) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let label: String
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                label = "系统通知权限已开启"
            case .denied:
                label = "系统通知权限未开启"
            case .notDetermined:
                label = "系统通知权限尚未请求"
            @unknown default:
                label = "系统通知权限状态未知"
            }
            DispatchQueue.main.async {
                completion(label)
            }
        }
    }

    func deliver(
        identifier: String = UUID().uuidString,
        title: String,
        body: String,
        shouldNotifyWhenAppActive: Bool
    ) {
        guard shouldNotifyWhenAppActive || !NSApp.isActive else { return }
        requestAuthorizationIfNeeded { granted in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    private func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                completion(true)
            case .denied:
                completion(false)
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    completion(granted)
                }
            @unknown default:
                completion(false)
            }
        }
    }
}

public enum AppNotificationBootstrap {
    public static func configure() {
        AppNotificationService.shared.configure()
    }
}
