# TEMP for macOS

A simple, native SwiftUI utility for temporary files and folders. **macOS only.** Requires macOS 14 or later.

## Open in Xcode

Open \`TEMP.xcodeproj\`, select the **TEMP** scheme and **My Mac**, then run. The repository includes the Xcode project: no package manager, project generator or external dependency is necessary.

## Features

- Import files or folders using the picker or drag and drop.
- Choose a default expiration: 15 minutes, 1 hour, 1 day, 7 days, 30 days or forever.
- Set a custom expiry per item, change expiration later, pin/unpin items.
- Open items or reveal them in Finder; in-place folders stay at their original location.
- See all items, items expiring in the next 24 hours and pinned items.
- A small menu bar menu keeps TEMP accessible after closing its window.
- Expired items are moved to the **macOS Trash**, not permanently deleted.

## Important safety and timing behavior

TEMP **copies individual files** into managed Application Support storage. Your original files stay untouched.

TEMP **does not copy folders**. After a clear confirmation, TEMP tracks each imported folder where it already exists using a security-scoped bookmark. An unpinned folder's expiration moves the **original folder and everything inside it** to macOS Trash. Pin a folder or select **Stop tracking (keep folder)** to prevent that action. Existing folders imported before this change remain legacy managed copies and never cause deletion of their original folders. If access to a tracked folder is lost, TEMP reports an error and does not remove the tracking record.

Automatic cleanup happens on launch and approximately every 30 seconds **while TEMP is running**, even when its main window is closed. If you fully quit TEMP or shut down your Mac, cleanup will resume next time TEMP launches. It does **not** install a background launch daemon or guarantee exact-second cleanup while quit.

You can restore items from the macOS Trash until Trash is emptied. TEMP's index removes them when it moves them to Trash, so a restored item would need to be imported again.

## Project layout

- \`TEMP/TEMPApp.swift\` — macOS app and menu bar menu
- \`TEMP/ContentView.swift\` — sidebar, file browser, import and expiration UI
- \`TEMP/TempItem.swift\` — metadata and expiration options
- \`TEMP/TemporaryStore.swift\` — sandboxed import, persistence, cleanup, Trash
- \`TEMP/TEMP.entitlements\` — App Sandbox and user-selected read-write access

## Next steps

The main UI follows Aura's responsive translucent sidebar, layered glass panels, and adaptive layouts. Test real folder security permissions and expiry on a Mac before distributing.

## CI configuration

The Xcode Cloud **Default** workflow builds TEMP for **macOS only** when changes are pushed to the repository. iOS and visionOS build actions are not part of the TEMP workflow.
