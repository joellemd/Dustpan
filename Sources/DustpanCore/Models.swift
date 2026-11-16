import Foundation

/// How confident we are that removing something costs the user nothing but a rebuild.
public enum Safety: String, Codable, Sendable {
    /// Rebuilt or re-downloaded automatically. Selected by default.
    case safe
    /// Might hold something the user wants. Never selected by default.
    case review
}

public enum RuleCategory: String, Codable, Sendable, CaseIterable {
    case xcode
    case packages
    case system

    public var title: String {
        switch self {
        case .xcode: return "Xcode"
        case .packages: return "Package managers"
        case .system: return "System"
        }
    }
}

public enum TargetMode: String, Codable, Sendable {
    /// The path itself is one removable item.
    case selfItem = "self"
    /// Each entry inside the path is a separate removable item; the folder stays.
    case children
}

/// One cleanup target, loaded from a JSON file in `Rules/`.
public struct Rule: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let category: RuleCategory
    public let safety: Safety
    /// One line on what this is.
    public let summary: String
    /// One line on what the user has to redo after removing it.
    public let afterEffect: String
    /// Paths, `~/` expands to the home folder.
    public let paths: [String]
    public let mode: TargetMode
    /// Only include items not modified for at least this many days.
    public let minAgeDays: Int?

    public init(
        id: String, name: String, category: RuleCategory, safety: Safety,
        summary: String, afterEffect: String, paths: [String],
        mode: TargetMode, minAgeDays: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.safety = safety
        self.summary = summary
        self.afterEffect = afterEffect
        self.paths = paths
        self.mode = mode
        self.minAgeDays = minAgeDays
    }
}

/// A file or folder found on disk that could be removed.
public struct ScanItem: Identifiable, Sendable, Hashable {
    public let url: URL
    public let size: Int64
    public let modified: Date?
    public var id: String { url.path }

    public init(url: URL, size: Int64, modified: Date? = nil) {
        self.url = url
        self.size = size
        self.modified = modified
    }
}

/// Everything one rule matched.
public struct RuleResult: Identifiable, Sendable {
    public let rule: Rule
    public let items: [ScanItem]
    public var id: String { rule.id }
    public var size: Int64 { items.reduce(0) { $0 + $1.size } }

    public init(rule: Rule, items: [ScanItem]) {
        self.rule = rule
        self.items = items
    }
}

/// Something the cleaner is asked to move to the Trash.
public struct CleanTarget: Sendable, Hashable {
    public let url: URL
    public let size: Int64
    /// Shown in History, e.g. "Xcode build data".
    public let label: String

    public init(url: URL, size: Int64, label: String) {
        self.url = url
        self.size = size
        self.label = label
    }
}
