import Foundation

/// Decides when to write `usage.json`. A launch from the panel carries a learned pick, so it saves
/// soon; an app switch only touches the Recent list, so switches are gathered into one write a
/// minute. Pure state, no timers: the caller schedules a single wake-up for `due`.
public struct SaveThrottle: Sendable, Equatable {
    public enum Urgency: Sendable {
        /// A launch from the panel: saved two seconds after the last one.
        case soon
        /// An app switch: saved within a minute, together with every other switch in that minute.
        case eventually
    }

    public static let soonDelay: TimeInterval = 2
    public static let eventualDelay: TimeInterval = 60

    /// When the pending changes should be written; nil when there are none.
    public private(set) var due: Date?

    public init() {}

    /// Notes a change. Returns the new due time when it moved, so the caller reschedules its
    /// wake-up, or nil when the wake-up already scheduled will carry this change too.
    public mutating func changed(_ urgency: Urgency, at now: Date) -> Date? {
        let target: Date
        switch urgency {
        case .soon:
            // Debounced: the latest launch sets it, and it also carries any pending switches.
            target = now.addingTimeInterval(Self.soonDelay)
        case .eventually:
            if due != nil { return nil }  // a save is already coming; it includes this
            target = now.addingTimeInterval(Self.eventualDelay)
        }
        guard target != due else { return nil }
        due = target
        return target
    }

    /// The scheduled wake-up arrived. True means write now.
    public mutating func fire(at now: Date) -> Bool {
        guard let due, due <= now else { return false }
        self.due = nil
        return true
    }

    /// Quitting, sleeping or logging out. True means there is something to write now.
    public mutating func flush() -> Bool {
        defer { due = nil }
        return due != nil
    }
}
