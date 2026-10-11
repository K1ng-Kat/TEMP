import AppKit
import SwiftUI

@main
struct TEMPApp: App {
    @StateObject private var store = TemporaryStore()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 850, minHeight: 590)
        }
        .defaultSize(width: 1040, height: 690)

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
        Text("TEMP is running")
        Text("\(store.items.count) items · \(store.expiringCount) expiring soon")
            .foregroundStyle(.secondary)

        Divider()

        Button("Open TEMP") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Clean Up Now") {
            store.cleanupExpired()
        }
        Divider()
        Button("Quit TEMP") {
            NSApp.terminate(nil)
        }
    }
}
