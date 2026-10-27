import Foundation
import LauncherCore

/// `usage.json` in Application Support. Saves two seconds after the last change, atomically and
/// off the main thread, keeping the previous good copy as `usage.json.bak`. A missing or unreadable
/// file means "start empty", never a crash.
@MainActor
final class UsageFile {
    let url: URL
    private var backup: URL { url.appendingPathExtension("bak") }
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.hus.spotty.usage", qos: .utility)

    init(url: URL = Storage.folder.appendingPathComponent("usage.json")) {
        self.url = url
    }

    func load() -> UsageStore {
        for candidate in [url, backup] {
            if let data = try? Data(contentsOf: candidate),
               let usage = try? JSONDecoder().decode(UsageStore.self, from: data) {
                return usage
            }
        }
        return UsageStore()
    }

    func scheduleSave(_ usage: UsageStore) {
        debugNote("usage save scheduled")
        pending?.cancel()
        let url = url, backup = backup
        let work = DispatchWorkItem { Self.write(usage, to: url, backup: backup) }
        pending = work
        queue.asyncAfter(deadline: .now() + 2, execute: work)
    }

    /// Writes now and waits, for quitting.
    func saveNow(_ usage: UsageStore) {
        pending?.cancel()
        pending = nil
        let url = url, backup = backup
        queue.sync { Self.write(usage, to: url, backup: backup) }
    }

    nonisolated private static func write(_ usage: UsageStore, to url: URL, backup: URL) {
        debugNote("usage save")
        guard let data = try? JSONEncoder().encode(usage) else { return }
        let files = FileManager.default
        try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Only a file that still decodes is worth keeping as the backup.
        if let old = try? Data(contentsOf: url), (try? JSONDecoder().decode(UsageStore.self, from: old)) != nil {
            try? old.write(to: backup, options: .atomic)
        }
        try? data.write(to: url, options: .atomic)
    }
}
