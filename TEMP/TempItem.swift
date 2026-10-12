import Foundation

/// What happens at expiration. The default is recoverable Trash.
enum ExpiryAction: String, Codable, CaseIterable {
    case moveToTrash
    case permanentlyDelete

    var title: String {
        switch self {
        case .moveToTrash: "Move to Trash"
        case .permanentlyDelete: "Permanently delete"
        }
    }
}

struct TempItem: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let isFolder: Bool
    let importedAt: Date
    var expiresAt: Date?
    var isPinned: Bool
    // Newly imported files and folders use this security-scoped bookmark to
    // access the original item after the app relaunches. Older items that lack
    // a bookmark remain managed copies and are never treated as originals.
    var folderBookmark: Data? = nil
    var sourcePath: String? = nil
    // Nil on existing records. Those always keep the original Trash behavior.
    // Each new import captures the user's choice so later Settings changes
    // cannot unexpectedly make already-tracked items irrecoverable.
    var expiryAction: ExpiryAction? = nil

    var effectiveExpiryAction: ExpiryAction { expiryAction ?? .moveToTrash }
    var permanentlyDeletesAtExpiry: Bool {
        !isPinned && effectiveExpiryAction == .permanentlyDelete
    }

    var isInPlaceItem: Bool { folderBookmark != nil }
    var isInPlaceFolder: Bool { isFolder && isInPlaceItem }
    var isLegacyCopy: Bool { !isInPlaceItem }

    var isExpiringSoon: Bool {
        guard !isPinned, let expiresAt else { return false }
        return expiresAt <= Date().addingTimeInterval(24 * 60 * 60)
    }

    var subtitle: String {
        isLegacyCopy ? (isFolder ? "Folder · legacy copy" : "File · legacy copy") : (isFolder ? "Folder · original" : "File · original")
    }
}

enum ExpirationPreset: String, CaseIterable, Identifiable {
    case fifteenMinutes
    case oneHour
    case oneDay
    case oneWeek
    case oneMonth
    case keepForever

    var id: Self { self }

    var title: String {
        switch self {
        case .fifteenMinutes: "15 minutes"
        case .oneHour: "1 hour"
        case .oneDay: "1 day"
        case .oneWeek: "7 days"
        case .oneMonth: "30 days"
        case .keepForever: "Keep forever"
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .fifteenMinutes: 15 * 60
        case .oneHour: 60 * 60
        case .oneDay: 24 * 60 * 60
        case .oneWeek: 7 * 24 * 60 * 60
        case .oneMonth: 30 * 24 * 60 * 60
        case .keepForever: nil
        }
    }

    func expirationDate(from now: Date = Date()) -> Date? {
        duration.map { now.addingTimeInterval($0) }
    }
}

enum TempSection: String, CaseIterable, Identifiable {
    case all
    case expiringSoon
    case pinned

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All items"
        case .expiringSoon: "Expiring soon"
        case .pinned: "Pinned"
        }
    }

    var icon: String {
        switch self {
        case .all: "square.stack.3d.up"
        case .expiringSoon: "clock.badge.exclamationmark"
        case .pinned: "pin"
        }
    }

    var detail: String {
        switch self {
        case .all: "Original files and folders scheduled for deletion"
        case .expiringSoon: "Items expiring in the next 24 hours"
        case .pinned: "Items you chose to keep"
        }
    }
}
