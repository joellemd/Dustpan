import Foundation

/// Free and total space on the volume holding the home folder.
public struct DiskSpace: Sendable {
    public let total: Int64
    public let free: Int64
    public var used: Int64 { max(0, total - free) }

    public static func current(
        at url: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> DiskSpace? {
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]), let total = values.volumeTotalCapacity,
            let free = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return DiskSpace(total: Int64(total), free: free)
    }
}

/// A plain-text list of what a clean would move, for checking before doing anything.
public enum DryRunReport {
    public static func text(for targets: [CleanTarget], date: Date = Date()) -> String {
        let total = targets.reduce(Int64(0)) { $0 + $1.size }
        var lines = [
            "Dustpan dry run",
            "Generated \(ISO8601DateFormatter().string(from: date))",
            "\(targets.count) item(s), \(DiskSize.format(total)) in total. Nothing has been moved.",
            "",
        ]
        let grouped = Dictionary(grouping: targets, by: { $0.label })
        for label in grouped.keys.sorted() {
            let items = (grouped[label] ?? []).sorted { $0.size > $1.size }
            let size = items.reduce(Int64(0)) { $0 + $1.size }
            lines.append("\(label) (\(DiskSize.format(size)))")
            for item in items {
                lines.append("  \(DiskSize.format(item.size))\t\(item.url.path)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
