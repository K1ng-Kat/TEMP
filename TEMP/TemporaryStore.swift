import AppKit
import Combine
import Foundation

/// Copies files into TEMP. New folders are tracked in place after clear consent.
/// Expiration moves managed copies or explicitly tracked original folders to Trash.
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

    func importURLs(_ urls: [URL], expiresAfter duration: TimeInterval?) {
        var imported = false
        var failures: [String] = []

        for source in urls where source.isFileURL {
            let hasAccess = source.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { source.stopAccessingSecurityScopedResource() }
            }

            let id = UUID()
            let name = source.lastPathComponent
            let isFolder = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isFolder {
                do {
                    // A security-scoped bookmark is required to access the same
                    // user-approved original folder after relaunching TEMP.
                    let bookmark = try source.bookmarkData(
                        options: [.withSecurityScope],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    items.append(TempItem(
                        id: id, name: name, isFolder: true,
                        importedAt: Date(),
                        expiresAt: duration.map { Date().addingTimeInterval($0) },
                        isPinned: duration == nil,
                        folderBookmark: bookmark,
                        sourcePath: source.path
                    ))
                    imported = true
                } catch {
                    failures.append("\(name): Can't retain access to this folder (\(error.localizedDescription)). Nothing was moved.")
                }
                continue
            }

            let container = managedURL.appendingPathComponent(id.uuidString, isDirectory: true)
            let destination = container.appendingPathComponent(name)
            do {
                try fileManager.createDirectory(at: container, withIntermediateDirectories: true)
                try fileManager.copyItem(at: source, to: destination)
                items.append(TempItem(
                    id: id, name: name, isFolder: false,
                    importedAt: Date(),
                    expiresAt: duration.map { Date().addingTimeInterval($0) },
                    isPinned: duration == nil
                ))
                imported = true
            } catch {
                try? fileManager.removeItem(at: container)
                failures.append("\(name): \(error.localizedDescription)")
            }
        }

        if imported { save() }
        if !failures.isEmpty {
            errorMessage = "Couldn't import:\n" + failures.joined(separator: "\n")
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
                    throw TEMPStorageError.missingFolder
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
                    throw TEMPStorageError.missingFolder
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

    /// Remove an in-place folder without moving it to Trash.
    func stopTracking(_ item: TempItem) {
        guard item.isInPlaceFolder else { return }
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
                try trashItem(item)
                removed.insert(item.id)
            } catch {
                errorMessage = "Couldn't clean up \(item.name): \(error.localizedDescription)"
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
        case missingFolder
        case missingBookmark

        var errorDescription: String? {
            switch self {
            case .lostPermission:
                return "TEMP no longer has permission to access that original folder. Re-import it to grant permission."
            case .missingFolder:
                return "The item is no longer at its saved location."
            case .missingBookmark:
                return "The folder's saved permission is missing."
            }
        }
    }

    private func withItemURL<T>(_ item: TempItem, _ action: (URL) throws -> T) throws -> T {
        guard item.isInPlaceFolder else {
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
        return try action(url)
    }

    private func trashItem(_ item: TempItem) throws {
        if item.isInPlaceFolder {
            try withItemURL(item) { url in
                guard fileManager.fileExists(atPath: url.path) else {
                    throw TEMPStorageError.missingFolder
                }
                // This is the actual user-selected original folder, not a copy.
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
