# TEMP for macOS

A simple, native SwiftUI utility for temporary files and folders. **macOS only.** Requires macOS 14 or later.

## Open in Xcode

Open \`TEMP.xcodeproj\`, select the **TEMP** scheme and **My Mac**, then run. The repository includes the Xcode project: no package manager, project generator or external dependency is necessary.

## Features

- Select files or folders with the picker or drag and drop, then confirm tracking of those originals.
- Choose a default expiration: 15 minutes, 1 hour, 1 day, 7 days, 30 days or forever.
- Set a custom expiry per item, change expiration later, pin/unpin items.
- Open or reveal tracked original items in Finder without duplicating them.
- See all items, items expiring in the next 24 hours and pinned items.
- A small menu bar menu keeps TEMP accessible after closing its window.
- Choose **Move to Trash** (default) or **Permanently delete** for newly tracked items in Settings. Permanent deletion is irreversible.

## Important safety and timing behavior

**New imports are original files and folders, not copies.** TEMP stores a bookmark granting access to the selected original item. The item stays at its current location until its timer expires. TEMP then either moves the actual original file or folder (including the folder's contents) into macOS Trash, or, when deliberately selected, permanently deletes it without using Trash.

Every selection displays an explicit warning and requires confirmation before it is tracked. Permanent deletion additionally requires confirmation to enable in Settings. You can pin an item, change its timer, or choose **Stop tracking (keep original)**. TEMP prevents overlapping file/folder records, rejects symbolic links and protected root locations, and does not silently remove records when a permission or deletion attempt fails.

**Permanent deletion safety:** Settings → When items expire offers **Permanently delete**, which calls macOS file removal directly on the selected original item. It recursively deletes folders and their contents without moving them to Trash; **there is no undo or Trash recovery**. The setting defaults to Move to Trash. It applies only to items imported **after** enabling it: every import records a deletion method at the time it is scheduled, and changes to Settings do not retroactively affect already tracked items. The import confirmation clearly warns when permanent deletion is selected; the file list marks the affected entries. Manual **Move to Trash** remains a recoverable action regardless of the expiration method.

**Migration safety:** Items added by older TEMP versions that lack a security-scoped bookmark remain legacy managed copies. Their original files remain untouched. Stop tracking or remove the older entry, then add the real original if you want it scheduled for deletion. Nothing is automatically converted.

Automatic cleanup happens on launch and approximately every 30 seconds **while TEMP is running**, even when its main window is closed. If you fully quit TEMP or shut down your Mac, cleanup will resume next time TEMP launches. It does **not** install a background launch daemon or guarantee exact-second cleanup while quit.

Items moved to Trash can be restored until Trash is emptied. Items permanently deleted cannot be recovered from Trash. TEMP's index removes successfully processed items, so a restored item must be scheduled again.

## Project layout

- \`TEMP/TEMPApp.swift\` — macOS app and menu bar menu
- \`TEMP/ContentView.swift\` — sidebar, file browser, import and expiration UI
- \`TEMP/TempItem.swift\` — metadata and expiration options
- \`TEMP/TemporaryStore.swift\` — sandboxed import, persistence, cleanup, Trash
- \`TEMP/TEMP.entitlements\` — App Sandbox and user-selected read-write access

## Next steps

The main window uses restrained native macOS navigation and file rows. Test security-scoped access, file and folder expiration, recoverable Trash and irreversible deletion with disposable test items on a Mac before distributing.

## CI configuration

The Xcode Cloud **Default** workflow builds TEMP for **macOS only** when changes are pushed to the repository. iOS and visionOS build actions are not part of the TEMP workflow.
