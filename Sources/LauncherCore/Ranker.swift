import Foundation

/// Anything the launcher can list: an app, later a Settings pane.
public struct Searchable: Sendable, Equatable, Identifiable {
    public let id: String  // bundle ID, stable across moves and updates
    public let name: String
    /// The display name first, then alternate names and your aliases.
    public let keys: [SearchKeys]

    public init(id: String, name: String, otherNames: [String] = []) {
        self.id = id
        self.name = name
        self.keys = ([name] + otherNames).map(SearchKeys.init)
    }
}

public struct Ranked: Sendable, Equatable {
    public let item: Searchable
    public let match: Match
    public let score: Double
    /// Times in a row you chose this app for exactly this query; 0 unless it is the taught app.
    /// Drives the "why" line: "You picked this for “ma” 4 times."
    public let pickCount: Int
    /// `Character` offsets in `item.name` to draw in bold. Empty when an alias matched.
    public let highlights: [Int]
}

public enum Ranker {
    /// Rows the panel shows, per the Quiet design.
    public static let rowLimit = 6
    /// Points per doubling of recent launches. At 20, about ten days of daily use lets an app
    /// matched at a word start overtake an unused app matched at the start of its name.
    static let frecencyWeight = 20.0
    /// Cap on the frecency bonus, so heavy use of "Notes Helper" can never outrank an exact "Notes".
    static let frecencyCap = 90.0
    /// Base points per strong tier; the 0...100 shape is added on top.
    static func tierBase(_ tier: MatchTier) -> Double {
        switch tier {
        case .exact: 300
        case .prefix: 200
        case .wordPrefix: 160
        case .initials: 150
        case .substring, .fuzzy: 0
        }
    }

    /// Orders matches in three bands: the app this exact query was taught to open, then strong
    /// matches by tier + shape + frecency, then weak matches by tier, then shape + frecency.
    public static func rank(_ query: QueryKeys, _ items: [Searchable], usage: UsageStore,
                            now: Date, limit: Int = rowLimit) -> [Ranked] {
        guard !query.isEmpty else { return [] }
        let taught = usage.pick(for: query, at: now)
        var ranked: [(band: Int, tier: Int, score: Double, item: Searchable, match: Match, key: Int)] = []
        for item in items {
            var best: (match: Match, key: Int)?
            for (k, keys) in item.keys.enumerated() {
                guard let m = Matcher.match(query, keys) else { continue }
                if let b = best, (b.match.tier, -b.match.shape) <= (m.tier, -m.shape) { continue }
                best = (m, k)
            }
            guard let best else { continue }
            let frecency = min(frecencyCap, frecencyWeight * log2(1 + usage.frecency(of: item.id, at: now)))
            let band: Int, tier: Int, score: Double
            if taught?.id == item.id {
                (band, tier, score) = (0, 0, 0)
            } else if best.match.tier.isStrong {
                (band, tier, score) = (1, 0, tierBase(best.match.tier) + Double(best.match.shape) + frecency)
            } else {
                (band, tier, score) = (2, best.match.tier.rawValue, Double(best.match.shape) + frecency)
            }
            ranked.append((band, tier, score, item, best.match, best.key))
        }
        ranked.sort {
            if $0.band != $1.band { return $0.band < $1.band }
            if $0.tier != $1.tier { return $0.tier < $1.tier }
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.item.name.count != $1.item.name.count { return $0.item.name.count < $1.item.name.count }
            return $0.item.name < $1.item.name
        }
        // Highlights cost a little more, so they are worked out for the visible rows only.
        return ranked.prefix(limit).map { r in
            Ranked(item: r.item, match: r.match, score: r.score,
                   pickCount: r.band == 0 ? taught?.count ?? 0 : 0,
                   highlights: r.key == 0 ? Matcher.highlights(query, r.item.keys[0]) : [])
        }
    }

    /// The grey text after the caret for the selected row. Tab accepts it by putting the full name in the field.
    public enum Completion: Equatable, Sendable {
        case none
        /// The name continues what you typed: "sa" shows "fari" after the caret.
        case suffix(String)
        /// The name doesn't start with what you typed, so the whole name is shown: "→ Visual Studio Code".
        case replace(String)
    }

    public static func completion(typed: String, name: String) -> Completion {
        let q = fold(typed)
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { return .none }
        var folded = ""
        var index = name.startIndex
        while index < name.endIndex, folded.unicodeScalars.count < q.unicodeScalars.count {
            folded += fold(String(name[index]))
            index = name.index(after: index)
        }
        guard folded == q else { return .replace(name) }
        return index == name.endIndex ? .none : .suffix(String(name[index...]))
    }
}
