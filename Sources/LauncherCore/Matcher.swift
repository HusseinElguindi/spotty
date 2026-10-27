/// How a query hit a name, strongest first. Tiers up to `.initials` are "strong":
/// usage can reorder them among themselves. Weak tiers always rank after strong ones.
public enum MatchTier: Int, Sendable, Comparable {
    case exact, prefix, wordPrefix, initials, substring, fuzzy

    public static func < (a: MatchTier, b: MatchTier) -> Bool { a.rawValue < b.rawValue }
    public var isStrong: Bool { self <= .initials }
}

public struct Match: Sendable, Equatable {
    public let tier: MatchTier
    /// Shape of the hit inside its tier, 0...100: earlier, tighter and shorter is higher.
    public let shape: Int
}

public enum Matcher {
    /// The strongest way `query` hits `name`, or nil when it doesn't match at all.
    public static func match(_ query: QueryKeys, _ name: SearchKeys) -> Match? {
        let q = query.compact, c = name.compact
        guard !q.isEmpty, q.count <= c.count else { return nil }
        let extra = c.count - q.count  // unmatched characters, a mild penalty everywhere

        if q == c {
            return Match(tier: .exact, shape: 100)
        }
        if c.starts(with: q) {
            return Match(tier: .prefix, shape: clamp(100 - extra))
        }
        if let word = name.wordOffsets.dropFirst().firstIndex(where: { c[$0...].starts(with: q) }) {
            return Match(tier: .wordPrefix, shape: clamp(100 - 8 * word - extra))
        }
        if query.words.count > 1, wordsInOrder(query.words, name) {
            return Match(tier: .wordPrefix, shape: clamp(90 - extra))
        }
        if name.initials.starts(with: q) {
            return Match(tier: .initials, shape: clamp(100 - 10 * (name.initials.count - q.count)))
        }
        if let at = firstIndex(of: q, in: c) {
            return Match(tier: .substring, shape: clamp(100 - 4 * at - extra))
        }
        if let score = fuzzyScore(q, name) {
            // A perfect run of word starts scores about 26 per character; scale to 0...100.
            return Match(tier: .fuzzy, shape: clamp(score * 100 / (26 * q.count)))
        }
        return nil
    }

    /// Every query word is a prefix of a later name word than the previous one: "vis code".
    static func wordsInOrder(_ words: [[Unicode.Scalar]], _ name: SearchKeys) -> Bool {
        var next = 0
        for word in words {
            guard next < name.wordOffsets.count,
                  let hit = name.wordOffsets[next...].firstIndex(where: { name.compact[$0...].starts(with: word) })
            else { return false }
            next = hit + 1
        }
        return true
    }

    static func firstIndex(of q: [Unicode.Scalar], in c: [Unicode.Scalar]) -> Int? {
        guard q.count <= c.count else { return nil }
        for i in 0...(c.count - q.count) where c[i] == q[0] && c[i...].starts(with: q) {
            return i
        }
        return nil
    }

    // Scoring for the fuzzy tier, in the spirit of fzf: every matched character earns points,
    // more at a word start or right after the previous match, and gaps cost points.
    static let matchPoints = 16, wordStartBonus = 10, consecutiveBonus = 6
    static let gapStart = 3, gapExtend = 1, leadingLimit = 6

    /// Best alignment of `q` as a subsequence of the name, by dynamic programming
    /// (O(query × name) with a running maximum for gaps), or nil if it isn't a subsequence.
    static func fuzzyScore(_ q: [Unicode.Scalar], _ name: SearchKeys) -> Int? {
        fuzzyAlign(q, name, trackPath: false)?.score
    }

    /// The same alignment, plus the matched positions in `compact` (for highlighting).
    static func fuzzyAlign(_ q: [Unicode.Scalar], _ name: SearchKeys,
                           trackPath: Bool = true) -> (score: Int, path: [Int])? {
        let c = name.compact, n = c.count
        let base = { (j: Int) in matchPoints + (name.wordStarts[j] ? wordStartBonus : 0) }
        // prev[j]: best score with the previous query character matched at j.
        // from[i][j]: where query character i - 1 sat in that best alignment.
        var prev = [Int?](repeating: nil, count: n)
        // Only kept for the few visible rows; ranking every app skips it.
        var from = trackPath ? [[Int]](repeating: [Int](repeating: -1, count: n), count: q.count) : []
        for j in 0..<n where c[j] == q[0] {
            prev[j] = base(j) - min(j, leadingLimit)
        }
        for i in q.indices.dropFirst() {
            var cur = [Int?](repeating: nil, count: n)
            var run: Int? = nil  // best prev[k] minus its gap cost, over k <= j - 2
            var runFrom = -1
            for j in 1..<n {
                if let r = run { run = r - gapExtend }
                if j >= 2, let p = prev[j - 2], p - gapStart > (run ?? Int.min) {
                    run = p - gapStart
                    runFrom = j - 2
                }
                guard c[j] == q[i] else { continue }
                let consecutive = prev[j - 1].map { $0 + consecutiveBonus }
                if let a = consecutive, a >= (run ?? Int.min) {
                    cur[j] = a + base(j)
                    if trackPath { from[i][j] = j - 1 }
                } else if let r = run {
                    cur[j] = r + base(j)
                    if trackPath { from[i][j] = runFrom }
                }
            }
            prev = cur
        }
        guard let end = prev.indices.filter({ prev[$0] != nil }).max(by: { prev[$0]! < prev[$1]! }) else { return nil }
        var path = [end]
        for i in stride(from: q.count - 1, to: 0, by: -1) where trackPath {
            path.insert(from[i][path[0]], at: 0)
        }
        return (prev[end]!, path)
    }

    /// `Character` offsets in the display name to draw in bold for this match, so the row
    /// shows why it matched. Empty when the hit came from an alias rather than the name.
    public static func highlights(_ query: QueryKeys, _ name: SearchKeys) -> [Int] {
        guard let m = match(query, name) else { return [] }
        let q = query.compact, c = name.compact
        var positions: [Int] = []
        switch m.tier {
        case .exact, .prefix:
            positions = Array(0..<q.count)
        case .wordPrefix:
            if let w = name.wordOffsets.dropFirst().first(where: { c[$0...].starts(with: q) }) {
                positions = Array(w..<(w + q.count))
            } else {
                var next = 0
                for word in query.words {
                    guard next < name.wordOffsets.count,
                          let hit = name.wordOffsets[next...].firstIndex(where: { c[$0...].starts(with: word) })
                    else { break }
                    positions += Array(name.wordOffsets[hit]..<(name.wordOffsets[hit] + word.count))
                    next = hit + 1
                }
            }
        case .initials:
            positions = Array(name.wordOffsets.prefix(q.count))
        case .substring:
            if let at = firstIndex(of: q, in: c) { positions = Array(at..<(at + q.count)) }
        case .fuzzy:
            positions = fuzzyAlign(q, name)?.path ?? []
        }
        return Array(Set(positions.map { name.charOffsets[$0] })).sorted()
    }

    private static func clamp(_ v: Int) -> Int { min(100, max(0, v)) }
}
