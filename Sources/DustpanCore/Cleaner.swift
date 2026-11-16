import Foundation

public struct HistoryEntry: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let label: String
    public let originalPath: String
    /// Where the item sits in the Trash. Nil if macOS did not report it.
    public let trashPath: String?
    public let size: Int64
    public var restored: Bool

    /// True while the item is still in the Trash and its old location is free.
    public var canRestore: Bool {
        guard !restored, let trashPath else { return false }
        let fm = FileManager.default
        return fm.fileExists(atPath: trashPath) && !fm.fileExists(atPath: originalPath)
    }
}

/// The log of everything Dustpan has moved to the Trash, kept as JSON in Application Support.
public struct HistoryStore: Sendable {
    public let file: URL

    public init(file: URL? = nil) {
        self.file = file ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dustpan/history.json")
    }

    public func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    public func save(_ entries: [HistoryEntry]) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: file, options: .atomic)
    }
}

public struct CleanReport: Sendable {
    public var moved: [HistoryEntry] = []
    /// Path and reason for everything that could not be moved.
    public var failures: [(path: String, reason: String)] = []
    public var freed: Int64 { moved.reduce(0) { $0 + $1.size } }
}

public enum CleanerError: LocalizedError {
    case notRestorable

    public var errorDescription: String? {
        "This item is no longer in the Trash, or something else now sits at its old location."
    }
}

/// The only type that changes anything on disk. It moves items to the Trash; it never deletes.
public struct Cleaner: Sendable {
    private let pathGuard: PathGuard
    private let history: HistoryStore

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        history: HistoryStore = HistoryStore()
    ) {
        self.pathGuard = PathGuard(home: home)
        self.history = history
    }

    public func moveToTrash(_ targets: [CleanTarget]) -> CleanReport {
        let fm = FileManager.default
        var report = CleanReport()

        for target in targets {
            guard pathGuard.isRemovable(target.url) else {
                report.failures.append((target.url.path, "Blocked by the safety check."))
                continue
            }
            guard fm.fileExists(atPath: target.url.path) else { continue }
            do {
                var resulting: NSURL?
                try fm.trashItem(at: target.url, resultingItemURL: &resulting)
                report.moved.append(HistoryEntry(
                    id: UUID(),
                    date: Date(),
                    label: target.label,
                    originalPath: target.url.path,
                    trashPath: resulting?.path,
                    size: target.size,
                    restored: false
                ))
            } catch {
                report.failures.append((target.url.path, error.localizedDescription))
            }
        }

        if !report.moved.isEmpty {
            try? history.save(report.moved + history.load())
        }
        return report
    }

    /// Puts an item back where it was, if it is still in the Trash.
    public func restore(_ entry: HistoryEntry) throws {
        guard entry.canRestore, let trashPath = entry.trashPath else { throw CleanerError.notRestorable }
        let fm = FileManager.default
        let destination = URL(fileURLWithPath: entry.originalPath)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: URL(fileURLWithPath: trashPath), to: destination)

        var entries = history.load()
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index].restored = true
            try history.save(entries)
        }
    }
}
