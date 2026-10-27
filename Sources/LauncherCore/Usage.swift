import Foundation

/// A count that halves every `halfLife`. Stores two numbers and decays lazily on read,
/// so nothing ever needs a background timer.
public struct DecayingCounter: Codable, Sendable, Equatable {
    public private(set) var value: Double
    public private(set) var updatedAt: Date

    public init(value: Double = 0, updatedAt: Date) {
        self.value = value
        self.updatedAt = updatedAt
    }

    public func value(at now: Date, halfLife: TimeInterval) -> Double {
        let age = max(0, now.timeIntervalSince(updatedAt))
        return value * pow(0.5, age / halfLife)
    }

    public mutating func add(_ amount: Double = 1, at now: Date, halfLife: TimeInterval) {
        value = value(at: now, halfLife: halfLife) + amount
        updatedAt = now
    }
}

/// The app a query has been taught to open first, and how many times in a row you chose it.
public struct Pick: Codable, Sendable, Equatable {
    public let id: String
    public fileprivate(set) var count: Int
    public fileprivate(set) var lastPicked: Date
}

/// Everything the launcher learns, saved as one small JSON file.
public struct UsageStore: Codable, Sendable, Equatable {
    public static let launchHalfLife: TimeInterval = 14 * 86_400
    /// A taught query that goes unused this long stops steering results.
    public static let pickExpiry: TimeInterval = 90 * 86_400
    public static let maxQueries = 500
    static let maxRecent = 50

    /// App id (bundle ID) -> how often it is opened from the launcher.
    public private(set) var launches: [String: DecayingCounter] = [:]
    /// Folded query -> the one app it opens first. The latest choice wins, as the design says.
    public private(set) var picks: [String: Pick] = [:]
    /// App id -> when it was last opened or brought to the front, for the empty-field list.
    public private(set) var lastUsed: [String: Date] = [:]

    public init() {}

    /// Records an open from the launcher. Returns true when it changed which app the query
    /// opens first, so the panel can confirm it ("“ma” now opens Maps first.").
    @discardableResult
    public mutating func recordLaunch(of id: String, query: QueryKeys, at now: Date) -> Bool {
        launches[id, default: DecayingCounter(updatedAt: now)].add(at: now, halfLife: Self.launchHalfLife)
        noteUse(of: id, at: now)
        guard !query.isEmpty else { return false }
        if var current = pick(for: query, at: now), current.id == id {
            current.count += 1
            current.lastPicked = now
            picks[query.key] = current
            return false
        }
        picks[query.key] = Pick(id: id, count: 1, lastPicked: now)
        if picks.count > Self.maxQueries { prune() }
        return true
    }

    /// Records that an app came to the front some other way (Dock, Cmd+Tab), for recents only.
    public mutating func noteUse(of id: String, at now: Date) {
        lastUsed[id] = now
        if lastUsed.count > Self.maxRecent {
            lastUsed = Dictionary(uniqueKeysWithValues: lastUsed.sorted { $0.value > $1.value }.prefix(Self.maxRecent).map { ($0.key, $0.value) })
        }
    }

    public func frecency(of id: String, at now: Date) -> Double {
        launches[id]?.value(at: now, halfLife: Self.launchHalfLife) ?? 0
    }

    public func pick(for query: QueryKeys, at now: Date) -> Pick? {
        guard let p = picks[query.key], now.timeIntervalSince(p.lastPicked) <= Self.pickExpiry else { return nil }
        return p
    }

    /// Most recently used app ids, newest first.
    public func recent(limit: Int = 5) -> [String] {
        lastUsed.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
    }

    /// Keeps the most recently used 80% of the cap.
    mutating func prune() {
        let keep = picks.sorted { $0.value.lastPicked > $1.value.lastPicked }.prefix(Self.maxQueries * 4 / 5)
        picks = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }
}
