import Foundation
import XCTest
@testable import LauncherCore

/// Fake `.app` bundles (just `Contents/Info.plist`) in a temporary folder.
final class AppScannerTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spotty-scan-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func makeApp(_ path: String, _ info: [String: Any], modified: Date? = nil) throws -> URL {
        let url = root.appendingPathComponent(path, isDirectory: true)
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        if let modified { try setModified(url, modified) }
        return url
    }

    func setModified(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    func scan(previous: AppScan = .empty) -> AppScan {
        AppScanner(roots: [root]).scan(previous: previous)
    }

    func testFindsAppsOneFolderDeep() throws {
        try makeApp("Fake One.app", ["CFBundleIdentifier": "test.one"])
        try makeApp("Utilities/Fake Two.app", ["CFBundleIdentifier": "test.two"])
        try makeApp("Vendor/Deeper/Too Deep.app", ["CFBundleIdentifier": "test.deep"])
        try makeApp(".Hidden.app", ["CFBundleIdentifier": "test.hidden"])
        XCTAssertEqual(scan().apps.map(\.name), ["Fake One", "Fake Two"])
    }

    func testSkipsHelpersAndBundlesWithoutAnID() throws {
        try makeApp("Helper.app", ["CFBundleIdentifier": "test.helper", "LSBackgroundOnly": true])
        try makeApp("Broken.app", ["CFBundleName": "Broken"])
        try makeApp("Real.app", ["CFBundleIdentifier": "test.real"])
        XCTAssertEqual(scan().apps.map(\.id), ["test.real"])
    }

    func testOtherNames() throws {
        try makeApp("Code.app", ["CFBundleIdentifier": "test.code", "CFBundleAlternateNames": ["VS Code"]])
        let app = try XCTUnwrap(scan().apps.first)
        XCTAssertEqual(app.name, "Code")
        XCTAssertEqual(app.otherNames, ["VS Code"])
    }

    func testFollowsLinksAndDropsDanglingOnes() throws {
        let real = try makeApp("Vendor/Linked.app", ["CFBundleIdentifier": "test.linked"])
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Linked.app"), withDestinationURL: real)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Gone.app"),
                                                   withDestinationURL: root.appendingPathComponent("Nowhere.app"))
        let apps = scan().apps
        XCTAssertEqual(apps.map(\.id), ["test.linked"])
        XCTAssertEqual(apps.first?.url.path, real.path)
    }

    func testOneEntryPerBundleIDNewestWins() throws {
        try makeApp("Old/Twin.app", ["CFBundleIdentifier": "test.twin"], modified: Date(timeIntervalSince1970: 1_000))
        let newer = try makeApp("New/Twin.app", ["CFBundleIdentifier": "test.twin"], modified: Date(timeIntervalSince1970: 2_000))
        let apps = scan().apps
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps.first?.url.path, newer.path)
        XCTAssertNil(apps.first?.subtitle)
    }

    func testSameNameDifferentAppsShowTheirFolder() throws {
        try makeApp("Work/Notes.app", ["CFBundleIdentifier": "test.notes.work"])
        try makeApp("Home/Notes.app", ["CFBundleIdentifier": "test.notes.home"])
        XCTAssertEqual(Set(scan().apps.compactMap(\.subtitle)), ["Work", "Home"])
    }

    func testSameNameSameFolderShowTheirFileName() throws {
        // Like Siri.app and "Siri AI.app", which Finder both calls Siri.
        try makeApp("Siri.app", ["CFBundleIdentifier": "test.siri", "CFBundleName": "Siri"])
        try makeApp("Siri Two.app", ["CFBundleIdentifier": "test.siri.two"])
        try makeApp("Other.app", ["CFBundleIdentifier": "test.other"])
        let apps = AppScanner(roots: [root]).scan().apps
        // Fake bundles have no localized names, so give one the other's name by hand.
        let renamed = apps.map { AppEntry(id: $0.id, name: $0.id == "test.siri.two" ? "Siri" : $0.name, url: $0.url, modified: $0.modified) }
        XCTAssertEqual(renamed.filter { $0.name == "Siri" }.count, 2)
        XCTAssertEqual(Set(AppScanner.subtitled(renamed).compactMap(\.subtitle)), ["Siri", "Siri Two"])
    }

    func testUnchangedBundlesAreNotReread() throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let url = try makeApp("Cached.app", ["CFBundleIdentifier": "test.cached", "CFBundleAlternateNames": ["Before"]], modified: date)
        let first = scan()
        // Rewrite the plist but keep the bundle's date: the scan must reuse what it had.
        try makeApp("Cached.app", ["CFBundleIdentifier": "test.cached", "CFBundleAlternateNames": ["After"]], modified: date)
        XCTAssertEqual(scan(previous: first).apps.first?.otherNames, ["Before"])
        try setModified(url, Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(scan(previous: first).apps.first?.otherNames, ["After"])
    }

    func testNoticesRootChanges() throws {
        let scanner = AppScanner(roots: [root])
        try setModified(root, Date(timeIntervalSince1970: 1_000))
        let first = scanner.scan()
        XCTAssertFalse(scanner.rootsChanged(since: first))
        try makeApp("New.app", ["CFBundleIdentifier": "test.new"])
        XCTAssertTrue(scanner.rootsChanged(since: first))
    }
}
