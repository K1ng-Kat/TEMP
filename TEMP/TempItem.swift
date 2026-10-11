import Foundation

struct TempItem: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let isFolder: Bool
    let importedAt: Date
    var expiresAt: Date?
    var isPinned: Bool

    var isExpiringSoon: Bool {
        guard !isPinned, let expiresAt else { return false }
        return expiresAt <= Date().addingTimeInterval(24 * 60 * 60)
    }

    var subtitle: String {
        isFolder ? "Folder" : "File"
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
        case .all: "Everything in your temporary library"
        case .expiringSoon: "Items expiring in the next 24 hours"
        case .pinned: "Items you chose to keep"
        }
    }
}
