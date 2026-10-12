import AppKit
import Darwin
import SwiftUI

// The launch agent runs THIS SAME signed executable headlessly. It never
// constructs a SwiftUI window or a menu bar icon.
if CommandLine.arguments.contains("--temp-background-cleanup") {
    Task { @MainActor in
        let store = TemporaryStore()
        store.cleanupExpired()
        await TEMPNotifications.finishPending()
        Darwin.exit(EXIT_SUCCESS)
    }
    RunLoop.main.run()
} else {
    TEMPApp.main()
}
