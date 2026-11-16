import CryptoKit
import Foundation

/// A set of the user's own files that take space and might no longer be wanted.
/// Nothing in a group is ever selected automatically.
public struct MediaGroup: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    /// Shown prominently when removal can't be undone by re-downloading or rebuilding.
    public let warning: String?
    public let items: [ScanItem]

    public var size: Int64 { items.reduce(0) { $0 + $1.size } }
}

/// Looks through the user's own folders for large or redundant files. Read-only.
public struct MediaScanner: Sendable {
    public let home: URL
    public var maxDepth = 6
    public var maxHashedFiles = 5_000
    private let pathGuard: PathGuard

    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "mkv", "avi", "webm"]
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "tiff", "tif", "psd", "gif", "bmp", "webp", "dng", "cr2", "nef", "arw",
    ]
    static let installerExtensions: Set<String> = ["dmg", "pkg", "iso", "xip"]
    static let archiveExtensions: Set<String> = ["zip"]
    static let skippedFolders: Set<String> = ["node_modules", "Pods", "Library", "DerivedData", "build", "target"]
    /// A folder holding one of these is a project; its assets are not loose media.
    static let projectMarkers = [
        ".git", "package.json", "ProjectSettings/ProjectVersion.txt", "pubspec.yaml", "Package.swift", "Cargo.toml",
    ]

    private struct FileInfo {
        let url: URL
        let size: Int64
        let logicalSize: Int
        let modified: Date
        let ext: String
        let name: String
    }

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        self.pathGuard = PathGuard(home: home)
    }

    public var defaultRoots: [URL] {
        ["Downloads", "Desktop", "Documents", "Movies", "Pictures"]
            .map { home.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func scan(roots: [URL]? = nil, now: Date = Date()) -> [MediaGroup] {
        let files = (roots ?? defaultRoots).flatMap { collect($0) }
        let day: TimeInterval = 86_400
        var claimed = Set<String>()

        func take(_ matches: [FileInfo]) -> [ScanItem] {
            matches
                .filter { claimed.insert($0.url.path).inserted }
                .map { ScanItem(url: $0.url, size: $0.size, modified: $0.modified) }
                .sorted { $0.size > $1.size }
        }
        func older(_ file: FileInfo, days: Double) -> Bool {
            file.modified <= now.addingTimeInterval(-days * day)
        }

        let installers = take(files.filter { Self.installerExtensions.contains($0.ext) })

        let recordings = take(files.filter {
            Self.videoExtensions.contains($0.ext) && $0.name.hasPrefix("Screen Recording") && older($0, days: 180)
        })

        let videos = take(files.filter {
            Self.videoExtensions.contains($0.ext) && $0.size > 500_000_000 && older($0, days: 365)
        })

        let screenshots = take(files.filter {
            Self.imageExtensions.contains($0.ext)
                && ($0.name.hasPrefix("Screenshot") || $0.name.hasPrefix("Screen Shot"))
                && older($0, days: 365)
        })

        let largeImages = take(files.filter {
            Self.imageExtensions.contains($0.ext) && $0.size > 20_000_000
        })

        let duplicates = take(duplicateImages(in: files.filter {
            Self.imageExtensions.contains($0.ext) && !claimed.contains($0.url.path)
        }))

        let archives = take(files.filter { file in
            guard Self.archiveExtensions.contains(file.ext) else { return false }
            var isDirectory: ObjCBool = false
            let unpacked = file.url.deletingPathExtension()
            return FileManager.default.fileExists(atPath: unpacked.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        })

        let groups = [
            MediaGroup(id: "installers", title: "Installers and disk images",
                       detail: ".dmg, .pkg, .iso and .xip files. Usually not needed once the app is installed.",
                       warning: nil, items: installers),
            MediaGroup(id: "screen-recordings", title: "Screen recordings older than 6 months",
                       detail: "Videos whose name starts with \"Screen Recording\".",
                       warning: nil, items: recordings),
            MediaGroup(id: "large-videos", title: "Large videos not changed in a year",
                       detail: "Video files over 500 MB.",
                       warning: nil, items: videos),
            MediaGroup(id: "large-images", title: "Large images and design exports",
                       detail: "Image files over 20 MB outside your Photos library.",
                       warning: nil, items: largeImages),
            MediaGroup(id: "phone-backups", title: "iPhone and iPad backups",
                       detail: "Local device backups made through Finder.",
                       warning: "A backup can't be recreated once removed.",
                       items: phoneBackups()),
            MediaGroup(id: "unpacked-archives", title: "Archives already unpacked",
                       detail: ".zip files with a folder of the same name beside them.",
                       warning: nil, items: archives),
            MediaGroup(id: "duplicate-images", title: "Duplicate images",
                       detail: "Byte-for-byte identical files. The oldest copy of each is kept and not listed.",
                       warning: nil, items: duplicates),
            MediaGroup(id: "old-screenshots", title: "Screenshots older than 1 year",
                       detail: "Images whose name starts with \"Screenshot\".",
                       warning: nil, items: screenshots),
        ]
        return groups.filter { !$0.items.isEmpty }.sorted { $0.size > $1.size }
    }

    // MARK: Collecting

    private func collect(_ root: URL) -> [FileInfo] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .fileSizeKey,
            .totalFileAllocatedSizeKey, .contentModificationDateKey,
        ]
        let keySet = Set(keys)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var files: [FileInfo] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keySet) else { continue }

            if values.isDirectory == true {
                let isProject = Self.projectMarkers.contains {
                    fm.fileExists(atPath: url.appendingPathComponent($0).path)
                }
                if enumerator.level >= maxDepth || isProject || Self.skippedFolders.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values.isRegularFile == true, pathGuard.isRemovable(url) else { continue }
            let ext = url.pathExtension.lowercased()
            guard Self.videoExtensions.contains(ext) || Self.imageExtensions.contains(ext)
                    || Self.installerExtensions.contains(ext) || Self.archiveExtensions.contains(ext)
            else { continue }

            files.append(FileInfo(
                url: url,
                size: Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0),
                logicalSize: values.fileSize ?? 0,
                modified: values.contentModificationDate ?? .distantPast,
                ext: ext,
                name: url.lastPathComponent
            ))
        }
        return files
    }

    // MARK: Duplicates

    /// Every copy except the oldest one in each set of identical images.
    private func duplicateImages(in images: [FileInfo]) -> [FileInfo] {
        let bySize = Dictionary(grouping: images.filter { $0.logicalSize >= 100_000 }, by: { $0.logicalSize })
        var budget = maxHashedFiles
        var extras: [FileInfo] = []

        for (_, sameSize) in bySize where sameSize.count > 1 {
            var byHash: [String: [FileInfo]] = [:]
            for file in sameSize {
                guard budget > 0 else { break }
                budget -= 1
                if let digest = hash(file.url) {
                    byHash[digest, default: []].append(file)
                }
            }
            for (_, identical) in byHash where identical.count > 1 {
                let oldestFirst = identical.sorted {
                    $0.modified == $1.modified ? $0.url.path < $1.url.path : $0.modified < $1.modified
                }
                extras.append(contentsOf: oldestFirst.dropFirst())
            }
        }
        return extras
    }

    private func hash(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Device backups

    private func phoneBackups() -> [ScanItem] {
        let folder = home.appendingPathComponent("Library/Application Support/MobileSync/Backup")
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        )) ?? []
        return entries.compactMap { url -> ScanItem? in
            guard pathGuard.isRemovable(url) else { return nil }
            let size = DiskSize.of(url)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return size > 0 ? ScanItem(url: url, size: size, modified: modified) : nil
        }
    }
}
