import AppKit
import DustpanCore
import Foundation
import Observation

/// What the review sheet shows before anything is moved.
struct ReviewRequest: Identifiable {
    struct Line: Identifiable {
        let id: String
        let title: String
        let detail: String
        let afterEffect: String
        let size: Int64
    }

    let id = UUID()
    let lines: [Line]
    let targets: [CleanTarget]

    var size: Int64 { targets.reduce(0) { $0 + $1.size } }
}

@MainActor
@Observable
final class AppModel {
    // Clean: things that rebuild themselves.
    var results: [RuleResult] = []
    var selectedRules: Set<String> = []
    var projects: [StaleProject] = []
    var selectedProjects: Set<String> = []
    var staleDays: Int
    var roots: [URL]

    // Find: the user's own apps and files. Never pre-selected.
    var apps: [UnusedApp] = []
    var selectedApps: Set<String> = []
    var appStaleDays: Int
    var media: [MediaGroup] = []
    var selectedMedia: Set<String> = []
    var toolchains: [Toolchain] = []
    var selectedToolVersions: Set<String> = []

    var history: [HistoryEntry] = []
    var disk: DiskSpace?
    var isScanning = false
    var lastScan: Date?
    var lastError: String?

    private let historyStore = HistoryStore()

    init() {
        let defaults = UserDefaults.standard
        let savedDays = defaults.integer(forKey: "staleDays")
        staleDays = savedDays > 0 ? savedDays : 90
        let savedAppDays = defaults.integer(forKey: "appStaleDays")
        appStaleDays = savedAppDays > 0 ? savedAppDays : 90

        if let saved = defaults.stringArray(forKey: "projectRoots") {
            roots = saved.map { URL(fileURLWithPath: $0) }
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            roots = ["Developer", "Projects", "Documents"]
                .map { home.appendingPathComponent($0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        history = historyStore.load()
        disk = DiskSpace.current()
    }

    // MARK: Totals

    var safeResults: [RuleResult] { results.filter { $0.rule.safety == .safe } }
    var safeSize: Int64 { safeResults.reduce(0) { $0 + $1.size } }
    var reviewSize: Int64 { results.filter { $0.rule.safety == .review }.reduce(0) { $0 + $1.size } }
    var cacheSize: Int64 { results.reduce(0) { $0 + $1.size } }
    var supersededToolSize: Int64 { supersededToolVersions.reduce(0) { $0 + $1.size } }
    /// Everything outside the Safe group: review rules plus the user's own projects, apps, SDKs and files.
    var reviewTotal: Int64 { reviewSize + projectSize + appsSize + supersededToolSize + mediaSize }

    func ruleIDs(category: RuleCategory, safety: Safety) -> [String] {
        results.filter { $0.rule.category == category && $0.rule.safety == safety }.map { $0.id }
    }

    func size(category: RuleCategory, safety: Safety) -> Int64 {
        results.filter { $0.rule.category == category && $0.rule.safety == safety }.reduce(0) { $0 + $1.size }
    }
    var projectSize: Int64 { projects.reduce(0) { $0 + $1.size } }
    var appsSize: Int64 { apps.reduce(0) { $0 + $1.totalSize } }
    var mediaSize: Int64 { media.reduce(0) { $0 + $1.size } }
    var toolchainSize: Int64 { toolchains.reduce(0) { $0 + $1.size } }
    var selectedToolSize: Int64 {
        toolchains.flatMap { $0.versions }.filter { selectedToolVersions.contains($0.id) }.reduce(0) { $0 + $1.size }
    }
    /// Versions that are neither the default nor the newest of their kind.
    var supersededToolVersions: [ToolVersion] {
        // A lone version is never "older"; Homebrew leftovers always are.
        toolchains.filter { $0.versions.count > 1 || $0.id == "brew-leftovers" }
            .flatMap { $0.versions }
            .filter { $0.isSuperseded }
    }

    var selectedCacheSize: Int64 {
        results.filter { selectedRules.contains($0.id) }.reduce(0) { $0 + $1.size }
    }
    var selectedProjectSize: Int64 {
        projects.filter { selectedProjects.contains($0.id) }.reduce(0) { $0 + $1.size }
    }
    var chosenApps: [UnusedApp] { apps.filter { selectedApps.contains($0.id) } }
    var selectedAppsSize: Int64 { chosenApps.reduce(0) { $0 + $1.totalSize } }
    var selectedAppsCacheSize: Int64 { chosenApps.reduce(0) { $0 + $1.cacheSize } }
    var selectedMediaSize: Int64 {
        media.flatMap { $0.items }.filter { selectedMedia.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    // MARK: Settings

    func persistSettings() {
        let defaults = UserDefaults.standard
        defaults.set(staleDays, forKey: "staleDays")
        defaults.set(appStaleDays, forKey: "appStaleDays")
        defaults.set(roots.map { $0.path }, forKey: "projectRoots")
    }

    func addRoot(_ url: URL) {
        guard !roots.contains(url) else { return }
        roots.append(url)
        persistSettings()
    }

    func removeRoot(_ url: URL) {
        roots.removeAll { $0 == url }
        persistSettings()
    }

    // MARK: Scanning

    /// Scans in stages so the quick results show up before the slow ones.
    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        let roots = self.roots
        let days = staleDays
        let appDays = appStaleDays
        var running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        if let own = Bundle.main.bundleIdentifier { running.insert(own) }
        let runningIDs = running

        let scanned = await Task.detached(priority: .userInitiated) { () -> ([RuleResult], [StaleProject]) in
            let caches = CacheScanner().scan(RuleStore.all())
            let projects = ProjectScanner().scan(roots: roots, staleDays: days)
            return (caches, projects)
        }.value
        results = scanned.0
        projects = scanned.1
        // Only things that rebuild themselves are ever pre-selected.
        selectedRules = Set(scanned.0.filter { $0.rule.safety == .safe }.map { $0.id })
        selectedProjects = Set(scanned.1.filter { $0.git == .clean }.map { $0.id })
        disk = DiskSpace.current()

        let foundApps = await Task.detached(priority: .userInitiated) {
            AppScanner().scan(unusedForDays: appDays, runningBundleIDs: runningIDs)
        }.value
        apps = foundApps
        selectedApps.formIntersection(foundApps.map { $0.id })

        let foundTools = await Task.detached(priority: .userInitiated) {
            ToolchainScanner().scan()
        }.value
        toolchains = foundTools
        selectedToolVersions.formIntersection(foundTools.flatMap { $0.versions }.map { $0.id })

        let foundMedia = await Task.detached(priority: .utility) {
            MediaScanner().scan()
        }.value
        media = foundMedia
        selectedMedia.formIntersection(foundMedia.flatMap { $0.items }.map { $0.id })

        lastScan = Date()
        isScanning = false
    }

    // MARK: Review requests

    func cacheReview(onlySafe: Bool = false) -> ReviewRequest {
        let chosen = onlySafe ? safeResults : results.filter { selectedRules.contains($0.id) }
        return ReviewRequest(
            lines: chosen.map {
                ReviewRequest.Line(
                    id: $0.id,
                    title: $0.rule.name,
                    detail: $0.items.count == 1 ? $0.items[0].url.path : "\($0.items.count) items",
                    afterEffect: $0.rule.afterEffect,
                    size: $0.size
                )
            },
            targets: chosen.flatMap { result in
                result.items.map { CleanTarget(url: $0.url, size: $0.size, label: result.rule.name) }
            }
        )
    }

    func projectReview() -> ReviewRequest {
        let chosen = projects.filter { selectedProjects.contains($0.id) }
        return ReviewRequest(
            lines: chosen.map {
                ReviewRequest.Line(
                    id: $0.id,
                    title: $0.name,
                    detail: "\($0.artifactNames) in \($0.url.path)",
                    afterEffect: "Dependencies and build output are recreated the next time you open or build the project.",
                    size: $0.size
                )
            },
            targets: chosen.flatMap { project in
                project.artifacts.map {
                    CleanTarget(url: $0.url, size: $0.size, label: "\(project.name) · \($0.url.lastPathComponent)")
                }
            }
        )
    }

    /// Uninstall the selected apps with their data, or clear only their caches.
    func appsReview(cachesOnly: Bool) -> ReviewRequest {
        let chosen = cachesOnly ? chosenApps.filter { $0.cacheSize > 0 } : chosenApps
        return ReviewRequest(
            lines: chosen.map { app in
                ReviewRequest.Line(
                    id: app.id,
                    title: app.name,
                    detail: cachesOnly
                        ? "Caches only. The app stays installed."
                        : "The app and \(app.data.count + app.caches.count) data location(s) in your Library.",
                    afterEffect: cachesOnly
                        ? "The app rebuilds its caches the next time you open it."
                        : (app.hasDocuments
                            ? "The app is gone, including documents stored inside it. Check those first."
                            : "The app is gone. Reinstall it to use it again; its settings start fresh."),
                    size: cachesOnly ? app.cacheSize : app.totalSize
                )
            },
            targets: chosen.flatMap { app -> [CleanTarget] in
                let caches = app.caches.map {
                    CleanTarget(url: $0.url, size: $0.size, label: "\(app.name) · cache")
                }
                if cachesOnly { return caches }
                let data = app.data.map {
                    CleanTarget(url: $0.url, size: $0.size, label: "\(app.name) · data")
                }
                return [CleanTarget(url: app.url, size: app.appSize, label: "\(app.name) · app")] + data + caches
            }
        )
    }

    func selectSupersededToolVersions() {
        selectedToolVersions = Set(supersededToolVersions.map { $0.id })
    }

    func toolchainReview() -> ReviewRequest {
        var lines: [ReviewRequest.Line] = []
        var targets: [CleanTarget] = []
        for toolchain in toolchains {
            for version in toolchain.versions where selectedToolVersions.contains(version.id) && version.removable {
                let label = "\(toolchain.name) \(version.version)"
                lines.append(ReviewRequest.Line(
                    id: version.id,
                    title: label,
                    detail: version.url.path,
                    afterEffect: version.isDefault
                        ? "This is your default version. Tools that rely on it stop working until you set another."
                        : "Projects pinned to this version need it again. To reinstall: \(toolchain.reinstallHint)",
                    size: version.size
                ))
                targets.append(CleanTarget(url: version.url, size: version.size, label: label))
            }
        }
        return ReviewRequest(lines: lines, targets: targets)
    }

    func mediaReview() -> ReviewRequest {
        var lines: [ReviewRequest.Line] = []
        var targets: [CleanTarget] = []
        for group in media {
            let chosen = group.items.filter { selectedMedia.contains($0.id) }
            guard !chosen.isEmpty else { continue }
            lines.append(ReviewRequest.Line(
                id: group.id,
                title: group.title,
                detail: chosen.count == 1 ? chosen[0].url.path : "\(chosen.count) files",
                afterEffect: group.warning ?? "These are your own files. Nothing recreates them once the Trash is emptied.",
                size: chosen.reduce(0) { $0 + $1.size }
            ))
            targets += chosen.map { CleanTarget(url: $0.url, size: $0.size, label: group.title) }
        }
        return ReviewRequest(lines: lines, targets: targets)
    }

    // MARK: Cleaning

    func clean(_ targets: [CleanTarget]) async {
        let report = await Task.detached(priority: .userInitiated) {
            Cleaner().moveToTrash(targets)
        }.value

        history = historyStore.load()
        if !report.failures.isEmpty {
            let first = report.failures.prefix(3).map { "\($0.path): \($0.reason)" }.joined(separator: "\n")
            lastError = "\(report.failures.count) item(s) could not be moved to the Trash.\n\(first)"
        }
        await scan()
    }

    func undo(_ entry: HistoryEntry) {
        do {
            try Cleaner().restore(entry)
        } catch {
            lastError = error.localizedDescription
        }
        history = historyStore.load()
    }
}
