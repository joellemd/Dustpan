import CoreServices
import Foundation

/// An installed app that has not been opened for a while, with the data it left in ~/Library.
public struct UnusedApp: Identifiable, Sendable {
    public let url: URL
    public let name: String
    public let bundleID: String
    /// When macOS last recorded the app being opened. Nil means it has no record of that.
    public let lastUsed: Date?
    /// The date used to decide staleness: last opened, else when it was added to this Mac.
    public let referenceDate: Date
    public let appSize: Int64
    /// Support files, containers, preferences and saved state.
    public let data: [ScanItem]
    /// Caches only. Safe to clear while keeping the app.
    public let caches: [ScanItem]
    /// The app's container holds a non-empty Documents folder.
    public let hasDocuments: Bool

    public var id: String { url.path }
    public var cacheSize: Int64 { caches.reduce(0) { $0 + $1.size } }
    public var dataSize: Int64 { data.reduce(0) { $0 + $1.size } + cacheSize }
    public var totalSize: Int64 { appSize + dataSize }

    public func daysUnused(now: Date = Date()) -> Int {
        max(0, Int(now.timeIntervalSince(referenceDate) / 86_400))
    }
}

/// Finds third-party apps that have not been opened for a given number of days. Read-only.
public struct AppScanner: Sendable {
    public let home: URL
    private let pathGuard: PathGuard

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        self.pathGuard = PathGuard(home: home)
    }

    /// - Parameters:
    ///   - runningBundleIDs: apps that are open right now; they are never listed.
    ///   - folders: where to look. Defaults to `/Applications` and `~/Applications`.
    public func scan(
        unusedForDays: Int,
        runningBundleIDs: Set<String> = [],
        folders: [URL]? = nil,
        now: Date = Date()
    ) -> [UnusedApp] {
        let fm = FileManager.default
        let cutoff = now.addingTimeInterval(-Double(unusedForDays) * 86_400)
        let searchFolders = folders ?? [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications"),
        ]
        var found: [UnusedApp] = []

        for folder in searchFolders {
            let entries = (try? fm.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]
            )) ?? []

            for appURL in entries where appURL.pathExtension.lowercased() == "app" {
                guard pathGuard.isRemovable(appURL),
                      let bundleID = Bundle(url: appURL)?.bundleIdentifier,
                      !bundleID.hasPrefix("com.apple."),
                      !runningBundleIDs.contains(bundleID)
                else { continue }

                let lastUsed = metadataDate(appURL, "kMDItemLastUsedDate")
                let added = metadataDate(appURL, "kMDItemDateAdded")
                    ?? (try? appURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                // Without any date we cannot tell how long it has sat there, so leave it alone.
                guard let reference = lastUsed ?? added, reference <= cutoff else { continue }

                let name = appURL.deletingPathExtension().lastPathComponent
                let container = home.appendingPathComponent("Library/Containers/\(bundleID)/Data/Documents")
                let documents = (try? fm.contentsOfDirectory(atPath: container.path)) ?? []

                found.append(UnusedApp(
                    url: appURL,
                    name: name,
                    bundleID: bundleID,
                    lastUsed: lastUsed,
                    referenceDate: reference,
                    appSize: DiskSize.of(appURL),
                    data: measure([
                        "Application Support/\(bundleID)",
                        "Application Support/\(name)",
                        "Containers/\(bundleID)",
                        "Preferences/\(bundleID).plist",
                        "Saved Application State/\(bundleID).savedState",
                        "HTTPStorages/\(bundleID)",
                        "WebKit/\(bundleID)",
                        "Logs/\(bundleID)",
                        "Logs/\(name)",
                    ]),
                    caches: measure([
                        "Caches/\(bundleID)",
                        "Caches/\(name)",
                    ]),
                    hasDocuments: !documents.filter { !$0.hasPrefix(".") }.isEmpty
                ))
            }
        }
        return found.sorted { $0.totalSize > $1.totalSize }
    }

    private func measure(_ libraryPaths: [String]) -> [ScanItem] {
        let library = home.appendingPathComponent("Library")
        var seen = Set<String>()
        return libraryPaths.compactMap { relative -> ScanItem? in
            let url = library.appendingPathComponent(relative)
            guard seen.insert(url.path).inserted,
                  FileManager.default.fileExists(atPath: url.path),
                  pathGuard.isRemovable(url)
            else { return nil }
            let size = DiskSize.of(url)
            return size > 0 ? ScanItem(url: url, size: size) : nil
        }
    }

    private func metadataDate(_ url: URL, _ attribute: String) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, attribute as CFString) as? Date
    }
}
