import Foundation
import LauncherCore

/// `usage.json` in Application Support, written atomically on a background queue, keeping the
/// previous good copy as `usage.json.bak`. A missing or unreadable file means "start empty",
/// never a crash.
///
/// When to write is `SaveThrottle`'s call: a launch from the panel saves two seconds after the
/// last one, while app switches (Recent only) are gathered into at most one write a minute.
/// Pending changes are flushed on quit, sleep and log out. Everything below the public methods
/// runs on `queue`, which is also where the single pending wake-up lives.
final class UsageFile: @unchecked Sendable {
    let url: URL
    private var backup: URL { url.appendingPathExtension("bak") }
    private let queue = DispatchQueue(label: "com.hus.spotty.usage", qos: .utility)

    // Touched only on `queue`.
    private var throttle = SaveThrottle()
    private var latest: UsageStore?
    private var wakeUp: DispatchWorkItem?
    private var lastWritten: Data?

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

    /// Notes a change; it is written when the throttle says so.
    func changed(_ usage: UsageStore, _ urgency: SaveThrottle.Urgency) {
        debugNote("usage changed")
        queue.async { [self] in
            latest = usage
            guard let due = throttle.changed(urgency, at: .now) else { return }
            wakeUp?.cancel()
            let work = DispatchWorkItem { [self] in
                if throttle.fire(at: .now) { writeLatest() }
            }
            wakeUp = work
            queue.asyncAfter(deadline: .now() + max(0, due.timeIntervalSinceNow), execute: work)
        }
    }

    /// Writes any pending change now and waits, for quitting, sleep and log out.
    func flush() {
        queue.sync { [self] in
            wakeUp?.cancel()
            wakeUp = nil
            if throttle.flush() { writeLatest() }
        }
    }

    /// Replaces whatever is pending with `usage` and writes it now, for "Reset learned ranking".
    func saveNow(_ usage: UsageStore) {
        queue.sync { [self] in
            wakeUp?.cancel()
            wakeUp = nil
            _ = throttle.flush()
            latest = usage
            writeLatest()
        }
    }

    private func writeLatest() {
        guard let usage = latest, let data = try? JSONEncoder().encode(usage) else { return }
        latest = nil
        // Nothing changed since the last write: leave the disk alone.
        guard data != lastWritten else { return }
        debugNote("usage save \(data.count) bytes")
        let files = FileManager.default
        try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Only a file that still decodes is worth keeping as the backup.
        if let old = try? Data(contentsOf: url), (try? JSONDecoder().decode(UsageStore.self, from: old)) != nil {
            try? old.write(to: backup, options: .atomic)
        }
        try? data.write(to: url, options: .atomic)
        lastWritten = data
    }
}
