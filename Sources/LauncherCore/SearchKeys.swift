import Foundation

/// Lowercase, accent-free and locale-independent, so "Café" finds "cafe" and a Turkish
/// locale can't turn "I" into a dotless "ı". Every string the matcher compares goes through this.
public func fold(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
}

/// One name an app can be found by, pre-split and folded once at index time
/// so a keystroke never re-processes it.
public struct SearchKeys: Sendable, Equatable {
    /// Folded name with separators removed: "Visual Studio Code" -> "visualstudiocode".
    public let compact: [Unicode.Scalar]
    /// `true` where a word starts in `compact`.
    public let wordStarts: [Bool]
    /// Offsets in `compact` where each word starts.
    public let wordOffsets: [Int]
    /// First letter of every word: "vsc".
    public let initials: [Unicode.Scalar]
    /// For each position in `compact`, the `Character` offset in the display name it came from,
    /// so matched letters can be highlighted in the row.
    public let charOffsets: [Int]

    public init(_ name: String) {
        var compact: [Unicode.Scalar] = []
        var starts: [Bool] = []
        var offsets: [Int] = []
        var initials: [Unicode.Scalar] = []
        var charOffsets: [Int] = []
        for (word, start) in splitWords(name) {
            let before = compact.count
            for (k, c) in word.enumerated() {
                for scalar in fold(String(c)).unicodeScalars {
                    compact.append(scalar)
                    charOffsets.append(start + k)
                    starts.append(compact.count - 1 == before)
                }
            }
            if compact.count > before {
                offsets.append(before)
                initials.append(compact[before])
            }
        }
        self.compact = compact
        self.wordStarts = starts
        self.wordOffsets = offsets
        self.initials = initials
        self.charOffsets = charOffsets
    }
}

/// What the user typed, folded once per keystroke.
public struct QueryKeys: Sendable {
    public let compact: [Unicode.Scalar]
    /// The query split on spaces, for "vis code" style queries.
    public let words: [[Unicode.Scalar]]
    /// The folded query with spaces kept, used as the key for learned picks.
    public let key: String

    public init(_ query: String) {
        let folded = fold(query.trimmingCharacters(in: .whitespaces))
        key = folded.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        words = folded.split(separator: " ").map { Array($0.unicodeScalars) }
        compact = words.flatMap { $0 }
    }

    public var isEmpty: Bool { compact.isEmpty }
}

/// Splits a display name into words at spaces and punctuation, at camelCase humps
/// ("TablePlus"), after an acronym ("HTTPToolkit" -> HTTP, Toolkit) and between
/// letters and digits ("1Password" -> 1, Password). Each word comes with the
/// `Character` offset where it starts.
func splitWords(_ name: String) -> [(word: String, offset: Int)] {
    enum Kind { case upper, lower, digit, other, separator }
    func kind(_ c: Character) -> Kind {
        if c.isUppercase { return .upper }
        if c.isLowercase { return .lower }
        if c.isNumber { return .digit }
        if c.isLetter { return .other }  // scripts without case, such as CJK
        return .separator
    }

    let chars = Array(name)
    var words: [(word: String, offset: Int)] = []
    var current = ""
    var start = 0
    for (i, c) in chars.enumerated() {
        let k = kind(c)
        if k == .separator {
            if !current.isEmpty { words.append((current, start)); current = "" }
            continue
        }
        if let last = current.last {
            let prev = kind(last)
            let next = i + 1 < chars.count ? kind(chars[i + 1]) : .separator
            let hump = prev == .lower && k == .upper
            let acronymEnd = prev == .upper && k == .upper && next == .lower
            let digitEdge = (prev == .digit) != (k == .digit)
            if hump || acronymEnd || digitEdge {
                words.append((current, start))
                current = ""
            }
        }
        if current.isEmpty { start = i }
        current.append(c)
    }
    if !current.isEmpty { words.append((current, start)) }
    return words
}
