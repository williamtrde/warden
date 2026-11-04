import Foundation
import UserNotifications
import WardenCore

/// Native notifications with direct Accept and Revert actions.
@MainActor
final class NotificationManager: NSObject {
    enum Action {
        case accept, revert, open
    }

    private static let category = "warden.change"
    private static let acceptAction = "warden.accept"
    private static let revertAction = "warden.revert"
    private static let pathKey = "path"

    private let center = UNUserNotificationCenter.current()
    private var handler: ((Action, String) -> Void)?

    func configure(handler: @escaping (Action, String) -> Void) {
        self.handler = handler
        center.delegate = self
        let accept = UNNotificationAction(identifier: Self.acceptAction, title: String(localized: "Accept"))
        let revert = UNNotificationAction(identifier: Self.revertAction, title: String(localized: "Revert"), options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [accept, revert], intentIdentifiers: [])
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// One notification per file: a newer change replaces the previous one.
    func post(_ change: PendingChange) {
        let content = UNMutableNotificationContent()
        let fileName = (change.path as NSString).lastPathComponent
        content.title = change.severity == .critical
            ? String(localized: "Critical change: \(fileName)")
            : String(localized: "Change: \(fileName)")
        content.body = change.explanation.firstSentence
        content.categoryIdentifier = Self.category
        content.userInfo = [Self.pathKey: change.path]
        content.sound = change.severity == .critical ? .default : nil
        center.add(UNNotificationRequest(identifier: change.path, content: content, trigger: nil))
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let path = response.notification.request.content.userInfo[Self.pathKey] as? String else { return }
        let identifier = response.actionIdentifier
        await MainActor.run {
            switch identifier {
            case Self.acceptAction: handler?(.accept, path)
            case Self.revertAction: handler?(.revert, path)
            default: handler?(.open, path)
            }
        }
    }
}
