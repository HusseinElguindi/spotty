import Foundation

/// One installed app, as the scanner found it.
public struct AppEntry: Identifiable, Sendable, Equatable {
    /// Bundle ID: stable across moves, renames and updates.
    public let id: String
    /// Localized display name, without ".app".
    public let name: String
    /// Resolved bundle path.
    public let url: URL
    /// `CFBundleAlternateNames`, plus the file name when it differs from the display name.
    public let otherNames: [String]
    /// The bundle's modification date; unchanged means the next scan skips re-reading it.
    public let modified: Date
    /// Grey text that tells apart two apps with one display name: their folder, or their file
    /// name when they share a folder too. Nil for every other app.
    public internal(set) var subtitle: String?

    public init(id: String, name: String, url: URL, otherNames: [String] = [], modified: Date, subtitle: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.otherNames = otherNames
        self.modified = modified
        self.subtitle = subtitle
    }
}

/// The result of one scan: every app, plus what the next scan needs to be cheap.
public struct AppScan: Sendable {
    public let apps: [AppEntry]
    /// Every bundle read, by resolved path, including duplicates that lost to a newer copy.
    public let byPath: [String: AppEntry]
    /// Each root folder's modification date at scan time. Adding, removing or renaming an app changes it.
    public let rootDates: [String: Date]

    public static let empty = AppScan(apps: [], byPath: [:], rootDates: [:])
}

/// A plain folder walk over the places apps live. Never asks Spotlight, never loads an icon.
public struct AppScanner: Sendable {
    /// Folders walked one level deep; a plain subfolder is walked one more level.
    public var roots: [URL]
    /// Bundles added directly, such as Finder.
    public var bundles: [URL]

    public init(roots: [URL], bundles: [URL] = []) {
        self.roots = roots
        self.bundles = bundles
    }

    /// The folders in docs/implementation.md.
    public static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AppScanner {
        AppScanner(roots: [
            "/Applications",
            home.appendingPathComponent("Applications").path,
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
            "/System/Library/CoreServices/Applications",
        ].map { URL(fileURLWithPath: $0, isDirectory: true) },
        bundles: [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app", isDirectory: true)])
    }

    /// The user folders, the only ones worth watching: the others sit on the sealed system volume.
    public static func watchedFolders(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String] {
        ["/Applications", home.appendingPathComponent("Applications").path]
    }

    /// Scans every root. Bundles whose modification date matches `previous` are reused untouched.
    public func scan(previous: AppScan = .empty) -> AppScan {
        var candidates: [URL] = bundles.compactMap(Self.resolve)
        var rootDates: [String: Date] = [:]
        for root in roots {
            rootDates[root.path] = Self.modified(root)
            candidates += Self.candidates(in: root, depth: 0)
        }

        var byPath: [String: AppEntry] = [:]
        func read(_ urls: [URL]) {
            for url in urls where byPath[url.path] == nil {
                guard let modified = Self.modified(url) else { continue }
                if let old = previous.byPath[url.path], old.modified == modified {
                    byPath[url.path] = old
                } else if let entry = Self.read(url, modified: modified) {
                    byPath[url.path] = entry
                }
            }
        }
        read(candidates)
        // Instruments, Simulator and friends live inside Xcode: in Contents/Applications since
        // Xcode 27, in Contents/Developer/Applications before that.
        let developerApps = byPath.values.filter { $0.id == "com.apple.dt.Xcode" }.flatMap { xcode in
            ["Contents/Applications", "Contents/Developer/Applications"]
                .map { xcode.url.appendingPathComponent($0, isDirectory: true) }
        }
        read(developerApps.flatMap { Self.candidates(in: $0, depth: 1) })

        // One entry per bundle ID: the newer copy wins.
        var byID: [String: AppEntry] = [:]
        for entry in byPath.values {
            if let other = byID[entry.id], (other.modified, other.url.path) >= (entry.modified, entry.url.path) { continue }
            byID[entry.id] = entry
        }
        let apps = Self.subtitled(byID.values.sorted { ($0.name, $0.url.path) < ($1.name, $1.url.path) })
        return AppScan(apps: apps, byPath: byPath, rootDates: rootDates)
    }

    /// Gives two different apps with one display name a subtitle each.
    static func subtitled(_ apps: [AppEntry]) -> [AppEntry] {
        var apps = apps
        let sameName = Dictionary(grouping: apps.indices, by: { apps[$0].name }).values.filter { $0.count > 1 }
        for group in sameName {
            let folders = group.map { apps[$0].url.deletingLastPathComponent().lastPathComponent }
            let distinct = Set(folders).count == folders.count
            for (i, folder) in zip(group, folders) {
                apps[i].subtitle = distinct ? folder : apps[i].url.deletingPathExtension().lastPathComponent
            }
        }
        return apps
    }

    /// True when any root folder changed since `scan`, at the cost of one `stat` per root.
    public func rootsChanged(since scan: AppScan) -> Bool {
        roots.contains { Self.modified($0) != scan.rootDates[$0.path] }
    }

    /// `.app` bundles directly in `folder`, and in its plain subfolders while `depth` is 0.
    static func candidates(in folder: URL, depth: Int) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var found: [URL] = []
        for entry in names {
            // A symlink or Finder alias is followed; one that dangles (an uninstaller's leftover) is dropped.
            guard let url = resolve(entry) else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue
            else { continue }
            if url.pathExtension == "app" {
                found.append(url)
            } else if depth == 0 {
                found += candidates(in: url, depth: 1)
            }
        }
        return found
    }

    static func resolve(_ url: URL) -> URL? {
        guard let resolved = try? URL(resolvingAliasFileAt: url) else { return nil }
        let path = resolved.resolvingSymlinksInPath()
        return FileManager.default.fileExists(atPath: path.path) ? path.standardizedFileURL : nil
    }

    static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Reads `Contents/Info.plist` directly rather than through `Bundle`, which caches one
    /// instance per path for the life of the process and would miss an app updating itself.
    static func read(_ url: URL, modified: Date) -> AppEntry? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let id = info["CFBundleIdentifier"] as? String, !id.isEmpty,
              info["LSBackgroundOnly"] as? Bool != true
        else { return nil }
        let fileName = url.deletingPathExtension().lastPathComponent
        // Finder's name in your language.
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        if name.isEmpty {
            name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? fileName
        }
        var others = info["CFBundleAlternateNames"] as? [String] ?? []
        if fileName != name { others.append(fileName) }
        return AppEntry(id: id, name: name, url: url, otherNames: others, modified: modified)
    }
}
