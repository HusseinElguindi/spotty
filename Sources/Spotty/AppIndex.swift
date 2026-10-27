import AppKit
import CoreServices
import LauncherCore
import os

/// Everything a keystroke searches, built whole off the main thread and swapped in at once.
struct AppIndex: Sendable {
    let scan: AppScan
    let searchables: [Searchable]
    private let byID: [String: AppEntry]

    static let empty = AppIndex(scan: .empty, aliases: [:])

    init(scan: AppScan, aliases: [String: [String]]) {
        self.scan = scan
        searchables = scan.apps.map {
            Searchable(id: $0.id, name: $0.name, otherNames: $0.otherNames + (aliases[$0.id] ?? []))
        }
        byID = Dictionary(scan.apps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func app(id: String) -> AppEntry? { byID[id] }
}

/// Keeps the index current. Every trigger (launch, FSEvents, wake, a stale open, a failed launch)
/// runs the same full rescan, made cheap by the modification-date cache, and only one at a time.
@MainActor
final class Indexer {
    private(set) var index = AppIndex.empty
    var onChange: ((AppIndex) -> Void)?

    private let scanner = AppScanner.standard()
    private let watcher = FolderWatcher()
    private var scanning = false
    private var dirty = false
    private var lastScan = Date.distantPast
    private var wakeObserver: NSObjectProtocol?
    nonisolated private static let log = Logger(subsystem: "com.hus.spotty", category: "index")
    nonisolated private static let signposts = OSSignposter(subsystem: "com.hus.spotty", category: "index")

    func start() {
        watcher.onChange = { [weak self] in self?.rescan() }
        watcher.start(AppScanner.watchedFolders())
        // Streams can go quiet across sleep, so start a fresh one and rescan on wake.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.watcher.stop()
                self.watcher.start(AppScanner.watchedFolders())
                self.rescan()
            }
        }
        rescan()
    }

    /// The cheap check when the panel opens: a `stat` per root covers a missed event.
    func checkIfStale() {
        guard Date.now.timeIntervalSince(lastScan) > 60 else { return }
        if scanner.rootsChanged(since: index.scan) { rescan() }
    }

    func rescan() {
        guard !scanning else { dirty = true; return }
        scanning = true
        dirty = false
        let previous = index.scan, scanner = scanner
        Task.detached(priority: .utility) {
            let state = Self.signposts.beginInterval("scan")
            let scan = scanner.scan(previous: previous)
            let index = AppIndex(scan: scan, aliases: Aliases.load())
            Self.signposts.endInterval("scan", state)
            await MainActor.run { self.finish(index) }
        }
    }

    private func finish(_ index: AppIndex) {
        self.index = index
        lastScan = .now
        scanning = false
        Self.log.info("Indexed \(index.scan.apps.count) apps")
        onChange?(index)
        if dirty { rescan() }
    }
}

/// `aliases.json` in Application Support: extra names by bundle ID, such as
/// `{"com.microsoft.VSCode": ["vs", "editor"]}`. Edit it by hand; a bad file means no aliases.
enum Aliases {
    static func load() -> [String: [String]] {
        guard let data = try? Data(contentsOf: Storage.folder.appendingPathComponent("aliases.json")),
              let aliases = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return aliases
    }
}

/// Directory-level FSEvents on the user's app folders. The 1 s latency lets FSEvents coalesce an
/// installer's burst of writes into one callback, so there is no timer of our own.
@MainActor
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    var onChange: (() -> Void)?

    func start(_ paths: [String]) {
        guard stream == nil else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.onChange?() }
        }
        stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone))
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}

/// Icons load lazily, only for the rows on screen, keyed by path plus modification date
/// so an updated app gets its new icon.
@MainActor
enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for app: AppEntry) -> NSImage {
        let key = "\(app.url.path)|\(app.modified.timeIntervalSince1970)" as NSString
        if let icon = cache.object(forKey: key) { return icon }
        let icon = NSWorkspace.shared.icon(forFile: app.url.path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}

/// `~/Library/Application Support/Spotty/`.
enum Storage {
    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Spotty", isDirectory: true)
}
