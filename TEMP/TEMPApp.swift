import AppKit
import SwiftUI
import UserNotifications

struct TEMPApp: App {
    @NSApplicationDelegateAdaptor(TEMPAppDelegate.self) private var appDelegate
    @StateObject private var store = TemporaryStore()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 780, minHeight: 570)
                .onAppear {
                    TEMPBackgroundController.shared.registerIfNeeded()
                }
        }
        .defaultSize(width: 1010, height: 700)

        MenuBarExtra("TEMP", systemImage: "hourglass") {
            TEMPMenuBarContent()
                .environmentObject(store)
        }
    }
}

private struct TEMPMenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: TemporaryStore

    var body: some View {
        Text("TEMP")
        Text("\(store.items.count) tracked · \(store.expiringCount) expiring soon")
            .foregroundStyle(.secondary)
        Divider()
        Button("Open TEMP") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Clean Up Now") { store.cleanupExpired() }
        Divider()
        Button("Quit TEMP window app") { NSApp.terminate(nil) }
    }
}


private final class TEMPAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
