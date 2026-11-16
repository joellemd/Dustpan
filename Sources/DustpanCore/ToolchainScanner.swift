import Foundation

/// One installed version of an SDK or toolchain.
public struct ToolVersion: Identifiable, Sendable {
    public let url: URL
    /// The version as shown to the user, e.g. "v20.11.0" or "Xcode 16.2".
    public let version: String
    public let size: Int64
    /// The version the version manager is set to use by default.
    public let isDefault: Bool
    /// The highest version installed, where versions can be ordered.
    public let isNewest: Bool
    /// False for entries Dustpan will not touch; those are listed for information only.
    public let removable: Bool
    /// Why it can't be removed here, or the command that removes it properly.
    public var lockReason: String? = nil

    public var id: String { url.path }
    /// An older version that is neither the default nor the newest.
    public var isSuperseded: Bool { removable && !isDefault && !isNewest }
}

/// All installed versions of one technology from one source, e.g. Node via nvm.
public struct Toolchain: Identifiable, Sendable {
    public let id: String
    public let name: String
    /// Where the versions come from, e.g. "nvm" or "Unity Hub".
    public let manager: String
    /// How to get a removed version back.
    public let reinstallHint: String
    public let versions: [ToolVersion]

    public var size: Int64 { versions.reduce(0) { $0 + $1.size } }
}

/// Lists installed SDK and toolchain versions by looking at where version managers keep them.
/// Read-only; it runs no tools except `xcode-select -p`.
public struct ToolchainScanner: Sendable {
    public let home: URL
    private let pathGuard: PathGuard

    private struct Source {
        let id: String
        let name: String
        let manager: String
        let reinstallHint: String
        /// Folders whose sub-folders are versions. `~/` is the home folder.
        let folders: [String]
        /// Only sub-folders with this prefix count.
        var prefix: String? = nil
        /// Whether folder names sort as versions.
        var ordered = true
        /// Outside the home folder.
        var system = false
    }

    private static let sources: [Source] = [
        Source(id: "node-nvm", name: "Node.js", manager: "nvm", reinstallHint: "nvm install <version>",
               folders: ["~/.nvm/versions/node"]),
        Source(id: "node-fnm", name: "Node.js", manager: "fnm", reinstallHint: "fnm install <version>",
               folders: ["~/Library/Application Support/fnm/node-versions", "~/.local/share/fnm/node-versions"]),
        Source(id: "node-volta", name: "Node.js", manager: "Volta", reinstallHint: "volta install node@<version>",
               folders: ["~/.volta/tools/image/node"]),
        Source(id: "python-pyenv", name: "Python", manager: "pyenv", reinstallHint: "pyenv install <version>",
               folders: ["~/.pyenv/versions"]),
        Source(id: "ruby-rbenv", name: "Ruby", manager: "rbenv", reinstallHint: "rbenv install <version>",
               folders: ["~/.rbenv/versions"]),
        Source(id: "ruby-rvm", name: "Ruby", manager: "RVM", reinstallHint: "rvm install <version>",
               folders: ["~/.rvm/rubies"], prefix: "ruby-"),
        Source(id: "rust", name: "Rust toolchains", manager: "rustup", reinstallHint: "rustup toolchain install <name>",
               folders: ["~/.rustup/toolchains"], ordered: false),
        Source(id: "flutter-fvm", name: "Flutter", manager: "FVM", reinstallHint: "fvm install <version>",
               folders: ["~/fvm/versions"]),
        Source(id: "go", name: "Go", manager: "go install golang.org/dl", reinstallHint: "go install golang.org/dl/<version>@latest",
               folders: ["~/sdk"], prefix: "go"),
        Source(id: "java-user", name: "Java JDKs", manager: "user install", reinstallHint: "Download the JDK again from its vendor.",
               folders: ["~/Library/Java/JavaVirtualMachines"]),
        Source(id: "java-system", name: "Java JDKs", manager: "system-wide", reinstallHint: "",
               folders: ["/Library/Java/JavaVirtualMachines"], system: true),
        Source(id: "android-platforms", name: "Android SDK platforms", manager: "Android Studio",
               reinstallHint: "Android Studio > SDK Manager", folders: ["~/Library/Android/sdk/platforms"], prefix: "android-"),
        Source(id: "android-build-tools", name: "Android build tools", manager: "Android Studio",
               reinstallHint: "Android Studio > SDK Manager", folders: ["~/Library/Android/sdk/build-tools"]),
        Source(id: "android-ndk", name: "Android NDK", manager: "Android Studio",
               reinstallHint: "Android Studio > SDK Manager", folders: ["~/Library/Android/sdk/ndk"]),
        Source(id: "android-system-images", name: "Android emulator images", manager: "Android Studio",
               reinstallHint: "Android Studio > SDK Manager", folders: ["~/Library/Android/sdk/system-images"], prefix: "android-"),
        Source(id: "unity", name: "Unity editors", manager: "Unity Hub", reinstallHint: "Unity Hub > Installs",
               folders: ["/Applications/Unity/Hub/Editor"], system: true),
    ]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        self.pathGuard = PathGuard(home: home)
    }

    /// - Parameter includeSystemLocations: also look in `/Applications` and `/Library`.
    public func scan(includeSystemLocations: Bool = true) -> [Toolchain] {
        var toolchains: [Toolchain] = []

        for source in Self.sources {
            if source.system && !includeSystemLocations { continue }
            let folders = versionFolders(of: source)
            guard !folders.isEmpty else { continue }

            let isDefault = defaultMatcher(for: source.id)
            let newest: String? = (source.ordered && folders.count > 1)
                ? folders.map { $0.lastPathComponent }.max { Self.isOlder($0, than: $1) }
                : nil

            let versions = folders.map { url -> ToolVersion in
                let name = url.lastPathComponent
                let removable = pathGuard.isRemovable(url)
                return ToolVersion(
                    url: url,
                    version: name,
                    size: DiskSize.of(url),
                    isDefault: isDefault(name),
                    isNewest: name == newest,
                    removable: removable,
                    lockReason: removable ? nil : "System-wide"
                )
            }
            .sorted { Self.isOlder($1.version, than: $0.version) }

            toolchains.append(Toolchain(
                id: source.id, name: source.name, manager: source.manager,
                reinstallHint: source.reinstallHint, versions: versions
            ))
        }

        if includeSystemLocations, let xcode = xcodeInstalls() {
            toolchains.append(xcode)
        }
        toolchains.sort { $0.size > $1.size }
        // Homebrew's long lists go last so the versioned SDKs stay on top.
        if includeSystemLocations {
            toolchains += HomebrewScanner(home: home).scan()
        }
        return toolchains
    }

    // MARK: Finding versions

    private func expand(_ path: String) -> URL {
        path.hasPrefix("~/") ? home.appendingPathComponent(String(path.dropFirst(2))) : URL(fileURLWithPath: path)
    }

    private func versionFolders(of source: Source) -> [URL] {
        source.folders.flatMap { folder -> [URL] in
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: expand(folder),
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            return entries.filter { url in
                // Aliases such as pyenv's "3.12 -> 3.12.4" are symlinks; only real folders are versions.
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true, values.isSymbolicLink != true
                else { return false }
                if let prefix = source.prefix { return url.lastPathComponent.hasPrefix(prefix) }
                return true
            }
        }
    }

    /// Compares names such as "v18.20.1", "go1.22.3" or "android-34" as versions.
    static func isOlder(_ a: String, than b: String) -> Bool {
        versionKey(a).compare(versionKey(b), options: .numeric) == .orderedAscending
    }

    private static func versionKey(_ name: String) -> String {
        guard let firstDigit = name.firstIndex(where: { $0.isNumber }) else { return name }
        return String(name[firstDigit...])
    }

    // MARK: Defaults

    private func defaultMatcher(for sourceID: String) -> (String) -> Bool {
        switch sourceID {
        case "node-nvm":
            // The alias may be partial ("20") or symbolic ("lts/*"); only numeric ones can be matched.
            guard var alias = firstLine(of: "~/.nvm/alias/default"),
                  alias.first.map({ $0.isNumber || $0 == "v" }) == true
            else { return { _ in false } }
            if !alias.hasPrefix("v") { alias = "v" + alias }
            return { $0 == alias || $0.hasPrefix(alias + ".") }

        case "python-pyenv":
            let names = lines(of: "~/.pyenv/version")
            return { names.contains($0) }

        case "ruby-rbenv":
            let names = lines(of: "~/.rbenv/version")
            return { names.contains($0) }

        case "rust":
            let line = lines(of: "~/.rustup/settings.toml").first { $0.hasPrefix("default_toolchain") }
            let parts = line?.split(separator: "\"") ?? []
            guard parts.count >= 2 else { return { _ in false } }
            let name = String(parts[1])
            return { $0 == name }

        case "flutter-fvm":
            let target = expand("~/fvm/default").resolvingSymlinksInPath().path
            return { target.hasSuffix("/versions/\($0)") }

        case "node-fnm":
            let targets = ["~/Library/Application Support/fnm/aliases/default", "~/.local/share/fnm/aliases/default"]
                .map { expand($0).resolvingSymlinksInPath().path }
            return { name in targets.contains { $0.contains("/node-versions/\(name)/") || $0.hasSuffix("/node-versions/\(name)") } }

        default:
            return { _ in false }
        }
    }

    private func lines(of path: String) -> [String] {
        guard let text = try? String(contentsOf: expand(path), encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private func firstLine(of path: String) -> String? {
        lines(of: path).first
    }

    // MARK: Xcode

    private func xcodeInstalls() -> Toolchain? {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Applications"), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        let apps = entries.filter { $0.pathExtension == "app" && $0.lastPathComponent.hasPrefix("Xcode") }
        guard !apps.isEmpty else { return nil }

        let selected = run("/usr/bin/xcode-select", ["-p"]) ?? ""
        let numbered = apps.map { url -> (url: URL, number: String) in
            let number = Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String
            return (url, number ?? "0")
        }
        let newest = numbered.count > 1 ? numbered.map { $0.number }.max { Self.isOlder($0, than: $1) } : nil

        let versions = numbered.map { entry -> ToolVersion in
            ToolVersion(
                url: entry.url,
                version: "\(entry.number) (\(entry.url.lastPathComponent))",
                size: DiskSize.of(entry.url),
                isDefault: selected.hasPrefix(entry.url.path + "/"),
                isNewest: entry.number == newest,
                removable: pathGuard.isRemovable(entry.url)
            )
        }
        .sorted { Self.isOlder($1.version, than: $0.version) }

        return Toolchain(
            id: "xcode", name: "Xcode", manager: "xcode-select",
            reinstallHint: "Download it again from the App Store or developer.apple.com.",
            versions: versions
        )
    }

    private func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
