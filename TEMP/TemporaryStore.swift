import AppKit
import Combine
import Foundation

/// Tracks approved original files and folders using security-scoped bookmarks.
/// Legacy managed copies remain separate and cannot delete their originals.
@MainActor
final class TemporaryStore: ObservableObject {
    @Published private(set) var items: [TempItem] = []
    @Published var errorMessage: String?

    private let fileManager = FileManager.default
    private let managedURL: URL
    private let indexURL: URL
    private var cleanupTimer: Timer?

    init() {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("TEMP", isDirectory: true)
        managedURL = root.appendingPathComponent("ManagedItems", isDirectory: true)
        indexURL = root.appendingPathComponent("items.json")

        do {
            try fileManager.createDirectory(
                at: managedURL,
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: indexURL.path) {
                let data = try Data(contentsOf: indexURL)
                items = try JSONDecoder().decode([TempItem].self, from: data)
            }
        } catch {
            errorMessage = "Unable to load TEMP's library: \(error.localizedDescription)"
        }

        cleanupExpired()
        // A running app also cleans while its window is closed. Quit means
        // cleanup resumes the next time TEMP launches.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.cleanupExpired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        cleanupTimer = timer
    }

    deinit {
        cleanupTimer?.invalidate()
    }

    var pinnedCount: Int {
        items.filter(\.isPinned).count
    }

    var expiringCount: Int {
        items.filter(\.isExpiringSoon).count
    }

    func items(in section: TempSection) -> [TempItem] {
        let filtered: [TempItem]
        switch section {
        case .all:
            filtered = items
        case .expiringSoon:
            filtered = items.filter(\.isExpiringSoon)
        case .pinned:
            filtered = items.filter(\.isPinned)
        }
        return filtered.sorted {
            if $0.isPinned != $1.isPinned { return !$0.isPinned }
            return ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture)
        }
    }

    // New items stay at their original locations; no duplicate gets created.
    func importURLs(
        _ urls: [URL],
        expiresAfter duration: TimeInterval?,
        expiryAction: ExpiryAction = .moveToTrash
    ) {
        var imported = false
        var failures: [String] = []

        for source in urls where source.isFileURL {
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }

            do {
                let original = source.standardizedFileURL
                try validateTrackableOriginal(original)
                let path = original.path

                // Avoid parent/child overlaps; a tracked folder includes all its contents.
                if items.contains(where: { record in
                    guard record.isInPlaceItem, let existing = record.sourcePath else { return false }
                    return existing == path ||
                           path.hasPrefix(existing + "/") ||
                           existing.hasPrefix(path + "/")
                }) {
                    throw TEMPStorageError.alreadyTracked
                }

                let isFolder = (try original.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
                let bookmark = try source.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                items.append(TempItem(
                    id: UUID(),
                    name: source.lastPathComponent,
                    isFolder: isFolder,
                    importedAt: Date(),
                    expiresAt: duration.map { Date().addingTimeInterval($0) },
                    isPinned: duration == nil,
                    folderBookmark: bookmark,
                    sourcePath: path,
                    expiryAction: expiryAction
                ))
                imported = true
            } catch {
                failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if imported { save() }
        if !failures.isEmpty {
            errorMessage = "Couldn't track these originals:\n" + failures.joined(separator: "\n")
        }
    }

    private func validateTrackableOriginal(_ url: URL) throws {
        let path = url.standardizedFileURL.path
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
        let support = managedURL.deletingLastPathComponent().standardizedFileURL.path

        // TEMP must never be able to schedule your whole home folder, a system
        // directory, its own database, or an immediate personal root folder.
        let protected: Set<String> = [
            "/", "/System", "/Library", "/Applications", "/Users", "/Volumes",
            home, home + "/Desktop", home + "/Documents", home + "/Downloads",
            home + "/Pictures", home + "/Music", home + "/Movies",
            home + "/Library", support, managedURL.standardizedFileURL.path
        ]
        guard !protected.contains(path),
              !path.hasPrefix(support + "/"),
              !path.hasPrefix(home + "/Library/") else {
            throw TEMPStorageError.protectedLocation
        }
        let values = try url.resourceValues(
            forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey]
        )
        guard values.isSymbolicLink != true,
              values.isDirectory == true || values.isRegularFile == true else {
            throw TEMPStorageError.unsupportedItem
        }
        guard fileManager.fileExists(atPath: url.path) else {
            throw TEMPStorageError.missingItem
        }
    }

    func setExpiration(for id: UUID, to date: Date?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].expiresAt = date
        items[index].isPinned = date == nil
        save()
        cleanupExpired()
    }

    func togglePin(for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if items[index].isPinned {
            items[index].isPinned = false
            items[index].expiresAt = Date().addingTimeInterval(24 * 60 * 60)
        } else {
            items[index].isPinned = true
            items[index].expiresAt = nil
        }
        save()
    }

    func open(_ item: TempItem) {
        do {
            try withItemURL(item) { url in
                guard fileManager.fileExists(atPath: url.path) else {
                    throw TEMPStorageError.missingItem
                }
                NSWorkspace.shared.open(url)
            }
        } catch {
            errorMessage = "Couldn't open \(item.name): \(error.localizedDescription)"
        }
    }

    func showInFinder(_ item: TempItem) {
        do {
            try withItemURL(item) { url in
                guard fileManager.fileExists(atPath: url.path) else {
                    throw TEMPStorageError.missingItem
                }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } catch {
            errorMessage = "Couldn't reveal \(item.name): \(error.localizedDescription)"
        }
    }

    func showLibraryInFinder() {
        NSWorkspace.shared.open(managedURL)
    }

    /// Stop tracking an original without moving it to Trash.
    func stopTracking(_ item: TempItem) {
        guard item.isInPlaceItem else { return }
        items.removeAll { $0.id == item.id }
        save()
    }

    func moveToTrash(_ item: TempItem) {
        do {
            try trashItem(item)
            items.removeAll { $0.id == item.id }
            save()
        } catch {
            errorMessage = "Couldn't move \(item.name) to Trash: \(error.localizedDescription)"
        }
    }

    func cleanupExpired() {
        let now = Date()
        let expired = items.filter {
            !$0.isPinned && ($0.expiresAt.map { $0 <= now } ?? false)
        }
        guard !expired.isEmpty else { return }

        var removed = Set<UUID>()
        for item in expired {
            do {
                switch item.effectiveExpiryAction {
                case .moveToTrash:
                    try trashItem(item)
                case .permanentlyDelete:
                    try permanentlyDeleteItem(item)
                }
                removed.insert(item.id)
            } catch {
                errorMessage = "Couldn't \(item.effectiveExpiryAction == .permanentlyDelete ? "permanently delete" : "move to Trash") \(item.name): \(error.localizedDescription)"
            }
        }
        if !removed.isEmpty {
            items.removeAll { removed.contains($0.id) }
            save()
        }
    }

    private func itemURL(for item: TempItem) -> URL {
        // The on-disk parent directory is always derived from the UUID,
        // never from a user-supplied absolute path.
        managedURL
            .appendingPathComponent(item.id.uuidString, isDirectory: true)
            .appendingPathComponent((item.name as NSString).lastPathComponent)
    }

    private enum TEMPStorageError: LocalizedError {
        case lostPermission
        case missingItem
        case missingBookmark
        case protectedLocation
        case unsupportedItem
        case alreadyTracked

        var errorDescription: String? {
            switch self {
            case .lostPermission:
                return "TEMP lost permission to this original item. Remove it and add it again."
            case .missingItem:
                return "The original item is no longer available."
            case .missingBookmark:
                return "TEMP no longer has a bookmark for this original item."
            case .protectedLocation:
                return "This is a protected system or personal root folder. Choose an individual item inside it."
            case .unsupportedItem:
                return "Only ordinary files and folders can be scheduled. Shortcuts and symbolic links aren't supported."
            case .alreadyTracked:
                return "This item, its parent folder, or its contents are already tracked."
            }
        }
    }

    private func withItemURL<T>(_ item: TempItem, _ action: (URL) throws -> T) throws -> T {
        guard item.isInPlaceItem else {
            return try action(itemURL(for: item))
        }
        guard let bookmark = item.folderBookmark else { throw TEMPStorageError.missingBookmark }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        guard url.startAccessingSecurityScopedResource() else {
            throw TEMPStorageError.lostPermission
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard !stale else { throw TEMPStorageError.lostPermission }
        try validateTrackableOriginal(url.standardizedFileURL)
        return try action(url)
    }

    private func trashItem(_ item: TempItem) throws {
        if item.isInPlaceItem {
            try withItemURL(item) { url in
                guard fileManager.fileExists(atPath: url.path) else {
                    throw TEMPStorageError.missingItem
                }
                // This is the actual user-selected original file or folder.
                try fileManager.trashItem(at: url, resultingItemURL: nil)
            }
        } else {
            let location = itemURL(for: item)
            let container = location.deletingLastPathComponent()
            if fileManager.fileExists(atPath: location.path) {
                try fileManager.trashItem(at: location, resultingItemURL: nil)
            }
            if fileManager.fileExists(atPath: container.path) {
                try fileManager.removeItem(at: container)
            }
        }
    }

    /// Never bypasses the same security-scoped URL and protected-path checks
    /// used by recoverable Trash. A deletion failure keeps the record for retry.
    private func permanentlyDeleteItem(_ item: TempItem) throws {
        try withItemURL(item) { url in
            guard fileManager.fileExists(atPath: url.path) else {
                throw TEMPStorageError.missingItem
            }

            // No system Trash: recursively removes the original item or the
            // old managed copy itself. This operation cannot be undone.
            try fileManager.removeItem(at: url)

            if item.isLegacyCopy {
                let container = url.deletingLastPathComponent()
                if fileManager.fileExists(atPath: container.path) {
                    try fileManager.removeItem(at: container)
                }
            }
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(items)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            errorMessage = "Couldn't save your TEMP library: \(error.localizedDescription)"
        }
    }
}
