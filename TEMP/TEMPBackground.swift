import Foundation
import ServiceManagement
import UserNotifications

// The agent runs the same signed TEMP executable as the main app, without a UI.
// SMAppService handles registration, approval and launch-at-login.
@MainActor
final class TEMPBackgroundController: ObservableObject {
    static let shared = TEMPBackgroundController()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var statusText = "Checking background service…"
    @Published private(set) var notificationsEnabled: Bool

    private let service = SMAppService.agent(plistName: "com.k1ngkat.temp.cleanup.plist")
    private let enabledKey = "TEMP.background.enabled"
    private let notificationsKey = "TEMP.notifications.enabled"

    private init() {
        let saved = UserDefaults.standard.object(forKey: enabledKey) as? Bool
        isEnabled = saved ?? true
        notificationsEnabled = UserDefaults.standard.bool(forKey: notificationsKey)
        updateStatus()
    }

    func registerIfNeeded() {
        guard isEnabled else {
            updateStatus()
            return
        }
        if service.status == .enabled {
            updateStatus()
            return
        }
        do {
            try service.register()
            updateStatus()
        } catch {
            statusText = "Background setup needs attention: \(error.localizedDescription)"
        }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        isEnabled = enabled
        if enabled {
            registerIfNeeded()
        } else {
            do {
                try service.unregister()
                updateStatus()
            } catch {
                statusText = "Couldn't stop background cleanup: \(error.localizedDescription)"
            }
        }
    }

    func updateStatus() {
        guard isEnabled else {
            statusText = "Disabled"
            return
        }
        switch service.status {
        case .enabled:
            statusText = "Enabled · checked about every minute while logged in"
        case .requiresApproval:
            statusText = "Needs approval in System Settings → Login Items"
        case .notRegistered:
            statusText = "Not registered — enable background cleanup"
        case .notFound:
            statusText = "Helper isn't in this app build"
        @unknown default:
            statusText = "Service status unavailable"
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        guard enabled else {
            notificationsEnabled = false
            UserDefaults.standard.set(false, forKey: notificationsKey)
            return
        }
        Task { @MainActor in
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )) ?? false
            UserDefaults.standard.set(granted, forKey: notificationsKey)
            notificationsEnabled = granted
            if !granted {
                statusText = "Allow TEMP notifications in System Settings to receive alerts."
            }
        }
    }
}

@MainActor
enum TEMPNotifications {
    private static var pending: [Task<Void, Never>] = []

    static func completed(_ item: TempItem) {
        let detail = item.effectiveExpiryAction == .permanentlyDelete ? "Permanently deleted" : "Moved to Trash"
        enqueue(
            title: "TEMP finished",
            body: "\(detail): \(item.name)",
            id: "temp.completed.\(item.id.uuidString)"
        )
    }

    static func failed(_ item: TempItem, message: String) {
        // A missing permission must not produce one warning every 60 seconds.
        let key = "TEMP.notice.failed.\(item.id.uuidString)"
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: key)
        guard now - last > 3_600 else { return }
        UserDefaults.standard.set(now, forKey: key)
        enqueue(
            title: "TEMP couldn't delete an item",
            body: "\(item.name): \(message)",
            id: "temp.failed.\(item.id.uuidString)"
        )
    }

    private static func enqueue(title: String, body: String, id: String) {
        guard UserDefaults.standard.bool(forKey: "TEMP.notifications.enabled") else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        pending.append(Task {
            try? await UNUserNotificationCenter.current().add(request)
        })
    }

    static func finishPending() async {
        let queued = pending
        pending.removeAll()
        for job in queued { await job.value }
    }
}
