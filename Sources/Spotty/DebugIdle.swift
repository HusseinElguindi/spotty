import Foundation

/// Tags the current main-thread wake with what Spotty did in it, for `SPOTTY_IDLE_TRACE`.
/// Compiles to nothing in release builds.
@inline(__always)
func debugNote(_ what: @autoclosure () -> String) {
    #if DEBUG
    DebugIdle.note(what())
    #endif
}

#if DEBUG
import AppKit

/// Development aid: `SPOTTY_IDLE_TRACE=1` logs every wake of the main run loop with its duration
/// and whatever Spotty's own callbacks noted during it. Untagged wakes are AppKit's or the system's.
enum DebugIdle {
    nonisolated(unsafe) private static var notes: [String] = []
    nonisolated(unsafe) private static var wokeAt: UInt64 = 0
    private static let enabled = ProcessInfo.processInfo.environment["SPOTTY_IDLE_TRACE"] != nil
    private static let lock = NSLock()

    static func note(_ what: String) {
        guard enabled else { return }
        if Thread.isMainThread {
            notes.append(what)
        } else {
            lock.lock(); defer { lock.unlock() }
            print(String(format: "%.3f bg %@", Date().timeIntervalSince1970, what))
            fflush(stdout)
        }
    }

    @MainActor static func start() {
        guard enabled else { return }
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { _, activity in
            if activity == .afterWaiting {
                wokeAt = DispatchTime.now().uptimeNanoseconds
                notes = []
            } else if wokeAt != 0 {
                let ms = Double(DispatchTime.now().uptimeNanoseconds - wokeAt) / 1e6
                print(String(format: "%.3f wake %.3fms %@", Date().timeIntervalSince1970, ms, notes.isEmpty ? "-" : notes.joined(separator: ",")))
                fflush(stdout)
                wokeAt = 0
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}
#endif
