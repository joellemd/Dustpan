import Foundation

/// Finds what each rule matches on disk and measures it. Read-only.
public struct CacheScanner: Sendable {
    public let home: URL
    private let pathGuard: PathGuard

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        self.pathGuard = PathGuard(home: home)
    }

    public func expand(_ path: String) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2))) }
        return URL(fileURLWithPath: path)
    }

    /// Results for rules that matched something, largest first.
    public func scan(_ rules: [Rule], now: Date = Date()) -> [RuleResult] {
        rules
            .map { scan($0, now: now) }
            .filter { !$0.items.isEmpty }
            .sorted { $0.size > $1.size }
    }

    public func scan(_ rule: Rule, now: Date = Date()) -> RuleResult {
        let fm = FileManager.default
        let cutoff = rule.minAgeDays.map { now.addingTimeInterval(-Double($0) * 86_400) }
        var items: [ScanItem] = []

        for path in rule.paths {
            let base = expand(path)
            guard fm.fileExists(atPath: base.path) else { continue }

            let candidates: [URL]
            switch rule.mode {
            case .selfItem:
                candidates = [base]
            case .children:
                candidates = (try? fm.contentsOfDirectory(
                    at: base, includingPropertiesForKeys: [.contentModificationDateKey]
                )) ?? []
            }

            for url in candidates where pathGuard.isRemovable(url) {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                if let cutoff {
                    guard let modified, modified <= cutoff else { continue }
                }
                let size = DiskSize.of(url)
                if size > 0 {
                    items.append(ScanItem(url: url, size: size, modified: modified))
                }
            }
        }

        return RuleResult(rule: rule, items: items.sorted { $0.size > $1.size })
    }
}
