import Foundation

/// Lists what Homebrew has installed by reading its Cellar and Caskroom folders.
/// Read-only, and it never runs `brew`.
public struct HomebrewScanner: Sendable {
    public let prefixes: [URL]
    private let pathGuard: PathGuard

    /// - Parameter prefixes: Homebrew install locations. Defaults to Apple silicon and Intel.
    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        prefixes: [URL] = [URL(fileURLWithPath: "/opt/homebrew"), URL(fileURLWithPath: "/usr/local")]
    ) {
        self.prefixes = prefixes
        self.pathGuard = PathGuard(home: home)
    }

    /// Up to three groups: old versions left behind (removable), every formula, every cask.
    public func scan() -> [Toolchain] {
        var leftovers: [ToolVersion] = []
        var formulae: [ToolVersion] = []
        var casks: [ToolVersion] = []

        for prefix in prefixes {
            for formula in folders(in: prefix.appendingPathComponent("Cellar")) {
                let name = formula.lastPathComponent
                let kegs = folders(in: formula)
                guard !kegs.isEmpty else { continue }

                // The version Homebrew points at; if that can't be read, assume the newest.
                let linked = prefix.appendingPathComponent("opt/\(name)").resolvingSymlinksInPath().lastPathComponent
                let newest = kegs.map { $0.lastPathComponent }.max { ToolchainScanner.isOlder($0, than: $1) }
                let hasLinked = kegs.contains(where: { $0.lastPathComponent == linked })
                let inUse = hasLinked ? linked : (newest ?? "")

                for keg in kegs {
                    let version = keg.lastPathComponent
                    if version == inUse {
                        formulae.append(ToolVersion(
                            url: keg, version: "\(name) \(version)", size: DiskSize.of(keg),
                            isDefault: false, isNewest: false, removable: false,
                            lockReason: "brew uninstall \(name)"
                        ))
                    } else {
                        let removable = pathGuard.isRemovable(keg)
                        leftovers.append(ToolVersion(
                            url: keg, version: "\(name) \(version)", size: DiskSize.of(keg),
                            isDefault: false, isNewest: false, removable: removable,
                            lockReason: removable ? nil : "Protected location"
                        ))
                    }
                }
            }

            for cask in folders(in: prefix.appendingPathComponent("Caskroom")) {
                let name = cask.lastPathComponent
                let versions = folders(in: cask)
                guard let newest = versions.max(by: {
                    ToolchainScanner.isOlder($0.lastPathComponent, than: $1.lastPathComponent)
                }) else { continue }
                casks.append(ToolVersion(
                    url: newest, version: "\(name) \(newest.lastPathComponent)", size: DiskSize.of(cask),
                    isDefault: false, isNewest: false, removable: false,
                    lockReason: "brew uninstall --cask \(name)"
                ))
            }
        }

        func byName(_ versions: [ToolVersion]) -> [ToolVersion] {
            versions.sorted { $0.version.localizedCaseInsensitiveCompare($1.version) == .orderedAscending }
        }

        return [
            Toolchain(id: "brew-leftovers", name: "Homebrew: old versions left behind", manager: "Homebrew",
                      reinstallHint: "brew install <formula>@<version>, where Homebrew still offers it.",
                      versions: leftovers.sorted { $0.size > $1.size }),
            Toolchain(id: "brew-formulae", name: "Homebrew formulae", manager: "Homebrew",
                      reinstallHint: "brew install <formula>", versions: byName(formulae)),
            Toolchain(id: "brew-casks", name: "Homebrew casks", manager: "Homebrew",
                      reinstallHint: "brew install --cask <cask>", versions: byName(casks)),
        ].filter { !$0.versions.isEmpty }
    }

    private func folders(in directory: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries.filter { url in
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
            return values.isDirectory == true && values.isSymbolicLink != true
        }
    }
}
