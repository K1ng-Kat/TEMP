import AppKit
import SwiftUI

@main
struct TEMPApp: App {
    @StateObject private var store = TemporaryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 850, minHeight: 590)
        }
        .defaultSize(width: 1040, height: 690)

        MenuBarExtra("TEMP", systemImage: "hourglass") {
            Text("TEMP is running")
            Text("\(store.items.count) items · \(store.expiringCount) expiring soon")
                .foregroundStyle(.secondary)

            Divider()

            Button("Open TEMP") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
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
}
