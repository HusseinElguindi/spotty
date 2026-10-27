import Foundation
import XCTest
@testable import LauncherCore

/// A realistic Applications folder.
let catalog: [Searchable] = [
    "Safari", "Slack", "Spotify", "System Settings", "Shortcuts", "Stickies", "Screenshot",
    "Terminal", "TextEdit", "TablePlus", "Notes", "Notes Helper", "Numbers", "Xcode", "Simulator",
    "Visual Studio Code", "CodeRunner", "1Password", "Finder", "FaceTime", "Font Book",
    "Google Chrome", "Firefox", "Microsoft Word", "Microsoft Excel", "Mail", "Maps", "Messages",
    "Music", "Photos", "Preview", "Calculator", "Calendar", "Activity Monitor", "App Store",
    "iTerm", "zoom.us", "HTTP Toolkit", "Keychain Access", "Disk Utility", "Système Préférences",
].map { Searchable(id: "id." + $0, name: $0, otherNames: $0 == "System Settings" ? ["System Preferences"] : []) }

let now = Date(timeIntervalSince1970: 1_800_000_000)

func top(_ query: String, usage: UsageStore = UsageStore(), at time: Date = now) -> String? {
    Ranker.rank(QueryKeys(query), catalog, usage: usage, now: time).first?.item.name
}

final class SplitTests: XCTestCase {
    func words(_ name: String) -> [String] { splitWords(name).map(\.word) }

    func testWords() {
        XCTAssertEqual(words("Visual Studio Code"), ["Visual", "Studio", "Code"])
        XCTAssertEqual(words("TablePlus"), ["Table", "Plus"])
        XCTAssertEqual(words("1Password"), ["1", "Password"])
        XCTAssertEqual(words("HTTPToolkit"), ["HTTP", "Toolkit"])
        XCTAssertEqual(words("iTerm"), ["i", "Term"])
        XCTAssertEqual(words("zoom.us"), ["zoom", "us"])
        XCTAssertEqual(words("Xcode"), ["Xcode"])
    }

    func testFoldingIsAccentAndCaseFree() {
        XCTAssertEqual(fold("Système Préférences"), "systeme preferences")
        XCTAssertEqual(fold("ISTANBUL"), "istanbul")
    }

    func testKeys() {
        let keys = SearchKeys("Visual Studio Code")
        XCTAssertEqual(String(String.UnicodeScalarView(keys.compact)), "visualstudiocode")
        XCTAssertEqual(String(String.UnicodeScalarView(keys.initials)), "vsc")
        XCTAssertEqual(keys.wordOffsets, [0, 6, 12])
        XCTAssertEqual(splitWords("Visual Studio Code").map(\.offset), [0, 7, 14])
    }
}

final class MatcherTests: XCTestCase {
    func tier(_ q: String, _ name: String) -> MatchTier? { Matcher.match(QueryKeys(q), SearchKeys(name))?.tier }

    func testTiers() {
        XCTAssertEqual(tier("notes", "Notes"), .exact)
        XCTAssertEqual(tier("saf", "Safari"), .prefix)
        XCTAssertEqual(tier("1pass", "1Password"), .prefix)
        XCTAssertEqual(tier("code", "Visual Studio Code"), .wordPrefix)
        XCTAssertEqual(tier("vis code", "Visual Studio Code"), .wordPrefix)
        XCTAssertEqual(tier("vsc", "Visual Studio Code"), .initials)
        XCTAssertEqual(tier("tudio", "Visual Studio Code"), .substring)
        XCTAssertEqual(tier("vstdo", "Visual Studio Code"), .fuzzy)
        XCTAssertEqual(tier("pref", "Système Préférences"), .wordPrefix)
        XCTAssertNil(tier("xyz", "Safari"))
        XCTAssertNil(tier("safarix", "Safari"))
    }

    func testFuzzyPrefersWordStartsAndRuns() {
        let q = QueryKeys("vscd")
        let good = Matcher.match(q, SearchKeys("Visual Studio Code"))!
        let poor = Matcher.match(q, SearchKeys("Avscdx"))!  // substring hit, a different tier
        XCTAssertEqual(good.tier, .fuzzy)
        XCTAssertEqual(poor.tier, .substring)
        let a = Matcher.fuzzyScore(Array("vscd".unicodeScalars), SearchKeys("Visual Studio Code"))!
        let b = Matcher.fuzzyScore(Array("vscd".unicodeScalars), SearchKeys("Overvisualsbscode"))!
        XCTAssertGreaterThan(a, b)
    }

    func testHighlightsShowWhyItMatched() {
        func bold(_ q: String, _ name: String) -> String {
            let on = Set(Matcher.highlights(QueryKeys(q), SearchKeys(name)))
            return String(name.enumerated().map { on.contains($0.offset) ? Character($0.element.uppercased()) : Character($0.element.lowercased()) })
        }
        XCTAssertEqual(bold("saf", "Safari"), "SAFari")
        XCTAssertEqual(bold("code", "Visual Studio Code"), "visual studio CODE")
        XCTAssertEqual(bold("vis code", "Visual Studio Code"), "VISual studio CODE")
        XCTAssertEqual(bold("vsc", "Visual Studio Code"), "Visual Studio Code")
        XCTAssertEqual(bold("tudio", "Visual Studio Code"), "visual sTUDIO code")
        XCTAssertEqual(bold("vstdo", "Visual Studio Code"), "Visual STuDiO code")
        XCTAssertEqual(bold("pref", "Système Préférences"), "système PRÉFérences")
        XCTAssertEqual(bold("tp", "TablePlus"), "TablePlus")
    }
}

final class GoldenQueryTests: XCTestCase {
    func testGoldenQueriesWithNoHistory() {
        let expected: [(String, String)] = [
            ("saf", "Safari"), ("vsc", "Visual Studio Code"), ("code", "CodeRunner"),
            ("settings", "System Settings"), ("system pref", "System Settings"),
            ("term", "Terminal"), ("notes", "Notes"), ("1pass", "1Password"),
            ("chrome", "Google Chrome"), ("word", "Microsoft Word"), ("ft", "FaceTime"),
            ("activity", "Activity Monitor"), ("http", "HTTP Toolkit"), ("zoom", "zoom.us"),
            ("iterm", "iTerm"), ("key", "Keychain Access"), ("s", "Slack"),
        ]
        for (query, app) in expected {
            XCTAssertEqual(top(query), app, "query \"\(query)\"")
        }
    }

    func testOnePickTeachesAQuery() {
        var usage = UsageStore()
        XCTAssertEqual(top("s"), "Slack", "with no history the shortest prefix match wins")
        usage.recordLaunch(of: "id.Safari", query: QueryKeys("s"), at: now)
        XCTAssertEqual(top("s", usage: usage), "Safari")
        XCTAssertEqual(top("S ", usage: usage), "Safari", "query keys are folded and trimmed")
    }

    func testPickOutranksABetterTier() {
        var usage = UsageStore()
        XCTAssertEqual(top("code"), "CodeRunner")
        usage.recordLaunch(of: "id.Visual Studio Code", query: QueryKeys("code"), at: now)
        XCTAssertEqual(top("code", usage: usage), "Visual Studio Code")
    }

    func testDailyUseLiftsAWordStartMatchOverAnUnusedPrefixMatch() {
        var usage = UsageStore()
        usage.recordLaunch(of: "id.Visual Studio Code", query: QueryKeys("vsc"), at: now)
        XCTAssertEqual(top("code", usage: usage), "CodeRunner", "one launch is not a habit")
        for day in 0..<14 {
            usage.recordLaunch(of: "id.Visual Studio Code", query: QueryKeys("vsc"),
                               at: now.addingTimeInterval(Double(day - 14) * 86_400))
        }
        XCTAssertEqual(top("code", usage: usage), "Visual Studio Code")
    }

    func testExactNameBeatsHeavilyUsedPrefixMatch() {
        var usage = UsageStore()
        for i in 0..<300 {
            usage.recordLaunch(of: "id.Notes Helper", query: QueryKeys("nh"), at: now.addingTimeInterval(Double(-i) * 3_600))
        }
        XCTAssertEqual(top("notes", usage: usage), "Notes")
        XCTAssertEqual(top("note", usage: usage), "Notes Helper", "but it does win among prefix matches")
    }

    func testLatestPickWinsAndCounts() {
        var usage = UsageStore()
        XCTAssertEqual(top("ma"), "Mail")
        XCTAssertTrue(usage.recordLaunch(of: "id.Maps", query: QueryKeys("ma"), at: now), "“ma” now opens Maps first.")
        XCTAssertFalse(usage.recordLaunch(of: "id.Maps", query: QueryKeys("ma"), at: now))
        let first = Ranker.rank(QueryKeys("ma"), catalog, usage: usage, now: now)[0]
        XCTAssertEqual(first.item.name, "Maps")
        XCTAssertEqual(first.pickCount, 2, "Maps is first because you picked it for “ma” 2 times.")
        XCTAssertEqual(Ranker.rank(QueryKeys("ma"), catalog, usage: usage, now: now)[1].pickCount, 0)
        XCTAssertTrue(usage.recordLaunch(of: "id.Mail", query: QueryKeys("ma"), at: now))
        XCTAssertEqual(top("ma", usage: usage), "Mail")
        XCTAssertEqual(Ranker.rank(QueryKeys("ma"), catalog, usage: usage, now: now)[0].pickCount, 1)
    }

    func testPicksExpireAfterThreeMonthsUnused() {
        var usage = UsageStore()
        usage.recordLaunch(of: "id.Safari", query: QueryKeys("s"), at: now)
        XCTAssertEqual(top("s", usage: usage, at: now.addingTimeInterval(60 * 86_400)), "Safari")
        XCTAssertEqual(top("s", usage: usage, at: now.addingTimeInterval(180 * 86_400)), "Slack")
    }

    func testSixRows() {
        XCTAssertEqual(Ranker.rank(QueryKeys("s"), catalog, usage: UsageStore(), now: now).count, 6)
    }

    func testRecentApps() {
        var usage = UsageStore()
        XCTAssertEqual(usage.recent(), [])
        for (i, id) in ["a", "b", "c", "d", "e", "f"].enumerated() {
            usage.noteUse(of: id, at: now.addingTimeInterval(Double(i)))
        }
        usage.recordLaunch(of: "b", query: QueryKeys("b"), at: now.addingTimeInterval(10))
        XCTAssertEqual(usage.recent(), ["b", "f", "e", "d", "c"])
        for i in 0..<80 { usage.noteUse(of: "x\(i)", at: now.addingTimeInterval(Double(100 + i))) }
        XCTAssertEqual(usage.lastUsed.count, UsageStore.maxRecent)
    }

    func testTabCompletion() {
        XCTAssertEqual(Ranker.completion(typed: "sa", name: "Safari"), .suffix("fari"))
        XCTAssertEqual(Ranker.completion(typed: "SA", name: "Safari"), .suffix("fari"))
        XCTAssertEqual(Ranker.completion(typed: "syste", name: "Système Préférences"), .suffix("me Préférences"))
        XCTAssertEqual(Ranker.completion(typed: "code", name: "Visual Studio Code"), .replace("Visual Studio Code"))
        XCTAssertEqual(Ranker.completion(typed: "safari", name: "Safari"), .none)
        XCTAssertEqual(Ranker.completion(typed: " ", name: "Safari"), .none)
    }

    func testUsageSurvivesJSON() throws {
        var usage = UsageStore()
        usage.recordLaunch(of: "id.Slack", query: QueryKeys("sl"), at: now)
        let data = try JSONEncoder().encode(usage)
        XCTAssertEqual(try JSONDecoder().decode(UsageStore.self, from: data), usage)
    }

    func testDecayHalvesPerHalfLife() {
        var c = DecayingCounter(updatedAt: now)
        c.add(at: now, halfLife: 10)
        XCTAssertEqual(c.value(at: now.addingTimeInterval(10), halfLife: 10), 0.5, accuracy: 1e-9)
        c.add(at: now.addingTimeInterval(10), halfLife: 10)
        XCTAssertEqual(c.value, 1.5, accuracy: 1e-9)
    }

    func testRankingSpeed() {
        // 500 apps, a 6-letter query, 200 keystrokes.
        let many = (0..<500).map { Searchable(id: "x\($0)", name: "Application Number \($0) Helper") } + catalog
        measure {
            for q in ["a", "ap", "app", "appl", "nmbr", "helper"] {
                for _ in 0..<33 { _ = Ranker.rank(QueryKeys(q), many, usage: UsageStore(), now: now) }
            }
        }
    }
}
