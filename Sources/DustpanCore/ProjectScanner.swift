import Foundation

/// A kind of project we recognise: if a marker file is present, the artifact folders
/// next to it can be rebuilt from source.
public struct ProjectKind: Sendable {
    public let name: String
    public let markers: [String]
    public let artifacts: [String]
    /// Whether sub-folders may hold further projects worth looking at.
    public let descend: Bool

    public static let all: [ProjectKind] = [
        ProjectKind(name: "Node", markers: ["package.json"],
                    artifacts: ["node_modules", ".next", ".nuxt", ".turbo"], descend: true),
        ProjectKind(name: "Unity", markers: ["ProjectSettings/ProjectVersion.txt"],
                    artifacts: ["Library", "Temp", "Logs", "obj"], descend: false),
        ProjectKind(name: "Flutter", markers: ["pubspec.yaml"],
                    artifacts: ["build", ".dart_tool"], descend: true),
        ProjectKind(name: "CocoaPods", markers: ["Podfile"],
                    artifacts: ["Pods"], descend: false),
        ProjectKind(name: "Swift package", markers: ["Package.swift"],
                    artifacts: [".build"], descend: false),
        ProjectKind(name: "Rust", markers: ["Cargo.toml"],
                    artifacts: ["target"], descend: false),
        ProjectKind(name: "Gradle", markers: ["build.gradle", "build.gradle.kts"],
                    artifacts: ["build", ".gradle"], descend: true),
    ]
}

public enum GitState: Sendable, Equatable {
    case clean
    case dirty(Int)
    /// Tracked by something other than Git (for example Plastic SCM); we can't tell if it is clean.
    case otherVCS
    case notARepo

    public var label: String {
        switch self {
        case .clean: return "Clean"
        case .dirty(let n): return n == 1 ? "1 uncommitted file" : "\(n) uncommitted files"
        case .otherVCS: return "Other version control"
        case .notARepo: return "Not a Git repo"
        }
    }
}

public struct StaleProject: Identifiable, Sendable {
    public let url: URL
    public let kinds: [String]
    public let artifacts: [ScanItem]
    public let lastChange: Date
    public let git: GitState

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
    public var size: Int64 { artifacts.reduce(0) { $0 + $1.size } }
    public var artifactNames: String { artifacts.map { $0.url.lastPathComponent }.joined(separator: ", ") }
}

/// Finds projects under the given folders whose rebuildable folders have sat untouched. Read-only.
public struct ProjectScanner: Sendable {
    public var maxDepth = 6
    private let pathGuard: PathGuard

    private static let packageExtensions: Set<String> = [
        "app", "framework", "bundle", "xcodeproj", "xcworkspace", "xcassets",
        "photoslibrary", "musiclibrary", "playground",
    ]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.pathGuard = PathGuard(home: home)
    }

    public func scan(roots: [URL], staleDays: Int, now: Date = Date()) -> [StaleProject] {
        let cutoff = now.addingTimeInterval(-Double(staleDays) * 86_400)
        var found: [StaleProject] = []
        var seen = Set<String>()
        for root in roots {
            walk(root.standardizedFileURL, depth: 0, cutoff: cutoff, found: &found, seen: &seen)
        }
        return found.sorted { $0.size > $1.size }
    }

    private func walk(_ dir: URL, depth: Int, cutoff: Date, found: inout [StaleProject], seen: inout Set<String>) {
        guard depth <= maxDepth else { return }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ) else { return }

        let matched = ProjectKind.all.filter { kind in
            kind.markers.contains { fm.fileExists(atPath: dir.appendingPathComponent($0).path) }
        }
        var skip: Set<String> = ["node_modules", "Pods"]

        if !matched.isEmpty {
            let names = Set(matched.flatMap { $0.artifacts })
            skip.formUnion(names)

            let artifactDirs = entries.filter { names.contains($0.lastPathComponent) && isRealDirectory($0) }
                .filter { pathGuard.isRemovable($0) }

            if !artifactDirs.isEmpty, seen.insert(dir.path).inserted {
                let last = lastChange(in: dir, artifacts: artifactDirs, skipping: names)
                if last <= cutoff {
                    let items = artifactDirs
                        .map { ScanItem(url: $0, size: DiskSize.of($0)) }
                        .filter { $0.size > 0 }
                        .sorted { $0.size > $1.size }
                    if !items.isEmpty {
                        found.append(StaleProject(
                            url: dir,
                            kinds: matched.map { $0.name },
                            artifacts: items,
                            lastChange: last,
                            git: gitState(of: dir)
                        ))
                    }
                }
            }
            if matched.contains(where: { !$0.descend }) && !matched.contains(where: { $0.descend }) { return }
        }

        for entry in entries {
            let name = entry.lastPathComponent
            if name.hasPrefix(".") || skip.contains(name) { continue }
            if Self.packageExtensions.contains(entry.pathExtension.lowercased()) { continue }
            guard isRealDirectory(entry) else { continue }
            walk(entry, depth: depth + 1, cutoff: cutoff, found: &found, seen: &seen)
        }
    }

    private func isRealDirectory(_ url: URL) -> Bool {
        guard let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return v.isDirectory == true && v.isSymbolicLink != true
    }

    /// Most recent modification among the project's source files (a shallow look), its Git index,
    /// and the artifact folders themselves, so a project you still build counts as in use.
    private func lastChange(in dir: URL, artifacts: [URL], skipping: Set<String>) -> Date {
        let fm = FileManager.default
        var latest = Date.distantPast
        var budget = 3_000

        func note(_ url: URL) {
            if let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               d > latest {
                latest = d
            }
        }

        func look(_ folder: URL, depth: Int) {
            guard depth <= 3, budget > 0,
                  let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey])
            else { return }
            for entry in entries {
                budget -= 1
                if budget <= 0 { return }
                let name = entry.lastPathComponent
                if name.hasPrefix(".") || skipping.contains(name) { continue }
                note(entry)
                if isRealDirectory(entry) { look(entry, depth: depth + 1) }
            }
        }

        note(dir)
        look(dir, depth: 1)
        note(dir.appendingPathComponent(".git/index"))
        for artifact in artifacts {
            note(artifact)
            let children = (try? fm.contentsOfDirectory(at: artifact, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for child in children.prefix(200) { note(child) }
        }
        return latest
    }

    private func gitState(of dir: URL) -> GitState {
        let fm = FileManager.default
        var hasGit = false
        var hasOther = false
        var current = dir
        while current.pathComponents.count > 1 {
            if fm.fileExists(atPath: current.appendingPathComponent(".git").path) { hasGit = true; break }
            if fm.fileExists(atPath: current.appendingPathComponent(".plastic").path)
                || fm.fileExists(atPath: current.appendingPathComponent(".svn").path)
                || fm.fileExists(atPath: current.appendingPathComponent(".hg").path) {
                hasOther = true
            }
            current = current.deletingLastPathComponent()
        }
        guard hasGit else { return hasOther ? .otherVCS : .notARepo }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", dir.path, "status", "--porcelain", "--", "."]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return .otherVCS
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return .otherVCS }

        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.isEmpty ? .clean : .dirty(lines.count)
    }
}
