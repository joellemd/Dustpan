import XCTest
@testable import DustpanCore

final class DustpanCoreTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("dustpan-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func write(_ relativePath: String, bytes: Int = 4096) throws {
        let url = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: url)
    }

    // MARK: PathGuard

    func testGuardRefusesHomeAndItsDirectChildren() {
        let guardian = PathGuard(home: home)
        XCTAssertFalse(guardian.isRemovable(home))
        XCTAssertFalse(guardian.isRemovable(home.appendingPathComponent("Documents")))
        XCTAssertFalse(guardian.isRemovable(home.appendingPathComponent(".npm")))
    }

    func testGuardRefusesWholeLibraryFolders() {
        let guardian = PathGuard(home: home)
        XCTAssertFalse(guardian.isRemovable(home.appendingPathComponent("Library/Caches")))
        XCTAssertTrue(guardian.isRemovable(home.appendingPathComponent("Library/Caches/Homebrew")))
    }

    func testGuardRefusesPathsOutsideHomeAndInTrash() {
        let guardian = PathGuard(home: home)
        XCTAssertFalse(guardian.isRemovable(URL(fileURLWithPath: "/usr/local/lib")))
        XCTAssertFalse(guardian.isRemovable(home.appendingPathComponent("a/../../elsewhere/x")))
        XCTAssertFalse(guardian.isRemovable(home.appendingPathComponent(".Trash/old/thing")))
    }

    func testGuardAllowsOnlyAppBundlesDirectlyInApplications() {
        let guardian = PathGuard(home: home)
        XCTAssertTrue(guardian.isRemovable(URL(fileURLWithPath: "/Applications/Example.app")))
        XCTAssertFalse(guardian.isRemovable(URL(fileURLWithPath: "/Applications")))
        XCTAssertFalse(guardian.isRemovable(URL(fileURLWithPath: "/Applications/Utilities")))
        XCTAssertFalse(guardian.isRemovable(URL(fileURLWithPath: "/Applications/Example.app/Contents")))
    }

    func testGuardAllowsOneUnityEditorVersionOnly() {
        let guardian = PathGuard(home: home)
        XCTAssertTrue(guardian.isRemovable(URL(fileURLWithPath: "/Applications/Unity/Hub/Editor/2022.3.10f1")))
        XCTAssertFalse(guardian.isRemovable(URL(fileURLWithPath: "/Applications/Unity/Hub/Editor")))
        XCTAssertFalse(guardian.isRemovable(URL(fileURLWithPath: "/Applications/Unity/Hub")))
    }

    // MARK: ToolchainScanner

    func testToolchainScannerMarksDefaultAndNewestNodeVersions() throws {
        try write(".nvm/versions/node/v18.20.1/bin/node")
        try write(".nvm/versions/node/v20.11.0/bin/node")
        try write(".nvm/versions/node/v22.3.0/bin/node")
        try write(".nvm/alias/default", bytes: 0)
        try "20\n".write(to: home.appendingPathComponent(".nvm/alias/default"), atomically: true, encoding: .utf8)

        let toolchains = ToolchainScanner(home: home).scan(includeSystemLocations: false)
        let node = try XCTUnwrap(toolchains.first { $0.id == "node-nvm" })

        XCTAssertEqual(node.versions.map { $0.version }, ["v22.3.0", "v20.11.0", "v18.20.1"])
        XCTAssertEqual(node.versions.filter { $0.isDefault }.map { $0.version }, ["v20.11.0"])
        XCTAssertEqual(node.versions.filter { $0.isNewest }.map { $0.version }, ["v22.3.0"])
        XCTAssertEqual(node.versions.filter { $0.isSuperseded }.map { $0.version }, ["v18.20.1"])
    }

    func testVersionOrderingIsNumeric() {
        XCTAssertTrue(ToolchainScanner.isOlder("v9.11.2", than: "v18.0.0"))
        XCTAssertTrue(ToolchainScanner.isOlder("android-9", than: "android-34"))
        XCTAssertFalse(ToolchainScanner.isOlder("go1.22.3", than: "go1.21.10"))
    }

    // MARK: HomebrewScanner

    func testGuardAllowsOneHomebrewKegOnly() {
        let guardian = PathGuard(home: home)
        XCTAssertTrue(guardian.isRemovable(URL(fileURLWithPath: "/opt/homebrew/Cellar/node/20.1.0")))
        XCTAssertTrue(guardian.isRemovable(URL(fileURLWithPath: "/usr/local/Cellar/node/20.1.0")))
        XCTAssertFalse(guardian.isRemovable(URL(fileURLWithPath: "/opt/homebrew/Cellar/node")))
        XCTAssertFalse(guardian.isRemovable(URL(fileURLWithPath: "/opt/homebrew/Cellar")))
        XCTAssertFalse(guardian.isRemovable(URL(fileURLWithPath: "/opt/homebrew/bin/node")))
        XCTAssertFalse(guardian.isRemovable(URL(fileURLWithPath: "/usr/local/lib/libfoo/1.0/x")))
    }

    func testHomebrewScannerSeparatesLinkedVersionFromLeftovers() throws {
        try write("brew/Cellar/node/20.1.0/bin/node")
        try write("brew/Cellar/node/22.3.0/bin/node")
        try write("brew/Cellar/wget/1.24.5/bin/wget")
        try write("brew/Caskroom/some-app/4.2/receipt.json", bytes: 100)
        let prefix = home.appendingPathComponent("brew")
        try FileManager.default.createDirectory(at: prefix.appendingPathComponent("opt"), withIntermediateDirectories: true)
        // Linked to the older version on purpose: the link decides, not the version number.
        try FileManager.default.createSymbolicLink(
            at: prefix.appendingPathComponent("opt/node"),
            withDestinationURL: prefix.appendingPathComponent("Cellar/node/20.1.0")
        )

        let groups = HomebrewScanner(home: home, prefixes: [prefix]).scan()
        let byID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })

        XCTAssertEqual(byID["brew-formulae"]?.versions.map { $0.version }, ["node 20.1.0", "wget 1.24.5"])
        XCTAssertEqual(byID["brew-formulae"]?.versions.filter { $0.removable }.count, 0)
        XCTAssertEqual(byID["brew-leftovers"]?.versions.map { $0.version }, ["node 22.3.0"])
        XCTAssertEqual(byID["brew-leftovers"]?.versions.first?.isSuperseded, true)
        XCTAssertEqual(byID["brew-casks"]?.versions.map { $0.version }, ["some-app 4.2"])
    }

    // MARK: MediaScanner

    func testMediaScannerGroupsInstallersArchivesAndDuplicates() throws {
        try write("Downloads/Setup.dmg", bytes: 50_000)
        try write("Downloads/photos.zip", bytes: 50_000)
        try write("Downloads/photos/readme.txt", bytes: 10)
        try write("Downloads/lonely.zip", bytes: 50_000)
        try write("Pictures/a.png", bytes: 200_000)
        try write("Pictures/copy/a-copy.png", bytes: 200_000)
        // Inside a project: must be ignored.
        try write("Documents/game/package.json", bytes: 10)
        try write("Documents/game/assets/Installer.dmg", bytes: 50_000)

        let roots = ["Downloads", "Pictures", "Documents"].map { home.appendingPathComponent($0) }
        let groups = MediaScanner(home: home).scan(roots: roots)
        let byID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })

        XCTAssertEqual(byID["installers"]?.items.map { $0.url.lastPathComponent }, ["Setup.dmg"])
        XCTAssertEqual(byID["unpacked-archives"]?.items.map { $0.url.lastPathComponent }, ["photos.zip"])
        XCTAssertEqual(byID["duplicate-images"]?.items.count, 1, "One of the two identical images is kept")
    }

    // MARK: Dry run

    func testDryRunReportListsEveryPath() {
        let targets = [
            CleanTarget(url: home.appendingPathComponent("Library/Caches/A"), size: 2_000, label: "Cache"),
            CleanTarget(url: home.appendingPathComponent("Downloads/b.dmg"), size: 1_000, label: "Installers"),
        ]
        let text = DryRunReport.text(for: targets)
        XCTAssertTrue(text.contains("Nothing has been moved"))
        for target in targets {
            XCTAssertTrue(text.contains(target.url.path))
        }
    }

    // MARK: CacheScanner

    func testChildrenRuleListsEachChildAndSkipsMissingPaths() throws {
        try write("Library/Developer/Xcode/DerivedData/AppA/build.o")
        try write("Library/Developer/Xcode/DerivedData/AppB/build.o")
        let rule = Rule(
            id: "dd", name: "DerivedData", category: .xcode, safety: .safe,
            summary: "", afterEffect: "",
            paths: ["~/Library/Developer/Xcode/DerivedData", "~/Library/Nope"],
            mode: .children
        )
        let result = CacheScanner(home: home).scan(rule)
        XCTAssertEqual(Set(result.items.map { $0.url.lastPathComponent }), ["AppA", "AppB"])
        XCTAssertGreaterThan(result.size, 0)
    }

    func testMinAgeKeepsRecentItemsOut() throws {
        try write("Library/Logs/Fresh/app.log")
        let rule = Rule(
            id: "logs", name: "Logs", category: .system, safety: .safe,
            summary: "", afterEffect: "", paths: ["~/Library/Logs"],
            mode: .children, minAgeDays: 30
        )
        let scanner = CacheScanner(home: home)
        XCTAssertTrue(scanner.scan(rule).items.isEmpty)
        let later = Date().addingTimeInterval(40 * 86_400)
        XCTAssertEqual(scanner.scan(rule, now: later).items.count, 1)
    }

    func testBuiltInRulesLoadAndStayInsideHome() {
        let rules = RuleStore.builtIn()
        XCTAssertFalse(rules.isEmpty)
        XCTAssertEqual(Set(rules.map { $0.id }).count, rules.count, "Rule ids must be unique")
        for rule in rules {
            for path in rule.paths {
                XCTAssertTrue(path.hasPrefix("~/"), "\(rule.id) has a path outside the home folder")
            }
        }
    }

    // MARK: ProjectScanner

    func testFindsArtifactsOnlyNextToAProjectFile() throws {
        try write("Code/web/package.json", bytes: 20)
        try write("Code/web/node_modules/lib/index.js")
        try write("Code/web/src/main.js", bytes: 20)
        try write("Code/notes/node_modules/stray.js")

        let later = Date().addingTimeInterval(100 * 86_400)
        let found = ProjectScanner(home: home)
            .scan(roots: [home.appendingPathComponent("Code")], staleDays: 90, now: later)

        XCTAssertEqual(found.map { $0.name }, ["web"])
        XCTAssertEqual(found.first?.artifacts.map { $0.url.lastPathComponent }, ["node_modules"])
        XCTAssertEqual(found.first?.git, .notARepo)
    }

    func testRecentlyChangedProjectIsNotStale() throws {
        try write("Code/web/package.json", bytes: 20)
        try write("Code/web/node_modules/lib/index.js")
        let found = ProjectScanner(home: home)
            .scan(roots: [home.appendingPathComponent("Code")], staleDays: 90)
        XCTAssertTrue(found.isEmpty)
    }
}
