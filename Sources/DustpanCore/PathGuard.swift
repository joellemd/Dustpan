import Foundation

/// Last line of defence: every path is checked here before it is moved to the Trash,
/// whatever a rule or a scanner says.
public struct PathGuard: Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home.standardizedFileURL
    }

    /// True only for:
    /// - an app bundle directly inside `/Applications`
    /// - one editor version inside `/Applications/Unity/Hub/Editor`
    /// - one version of one formula inside Homebrew's `Cellar`
    /// - paths safely inside the home folder:
    ///   - never the home folder itself or one of its direct children (`~/Documents`, `~/.npm`)
    ///   - never a direct child of `~/Library` (`~/Library/Caches` as a whole)
    ///   - never anything already in the Trash
    public func isRemovable(_ url: URL) -> Bool {
        let target = url.standardizedFileURL.pathComponents

        if target.count == 3, target[0] == "/", target[1] == "Applications",
           target[2].lowercased().hasSuffix(".app") {
            return true
        }

        // One Unity editor version installed by Unity Hub.
        if target.count == 6, Array(target.prefix(5)) == ["/", "Applications", "Unity", "Hub", "Editor"] {
            return true
        }

        // One version of one Homebrew formula: <prefix>/Cellar/<formula>/<version>.
        if target.count == 6,
           Array(target.prefix(4)) == ["/", "opt", "homebrew", "Cellar"]
            || Array(target.prefix(4)) == ["/", "usr", "local", "Cellar"] {
            return true
        }

        let base = home.pathComponents
        guard target.count > base.count, Array(target.prefix(base.count)) == base else { return false }

        let relative = Array(target.dropFirst(base.count))
        if relative.contains("..") || relative.contains(".") { return false }
        guard relative.count >= 2 else { return false }
        if relative[0] == ".Trash" { return false }
        if relative[0] == "Library" && relative.count < 3 { return false }
        return true
    }
}
