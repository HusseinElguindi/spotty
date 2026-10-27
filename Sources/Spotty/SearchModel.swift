import Foundation
import LauncherCore
import Observation

/// What the panel shows under the field, exactly one at a time.
enum Tray: Equatable {
    /// Empty field: up to five recent apps, ⌘1 to ⌘5.
    case recent([AppEntry])
    /// A search: at most six rows.
    case apps([AppRow])
    /// A sum replaces the list entirely.
    case math(expression: String, outcome: CalcOutcome)
    /// "Nothing matches “zzz”."
    case nothing
}

struct AppRow: Identifiable, Equatable {
    let app: AppEntry
    /// Times this query was taught this app, for the why line; 0 for every other row.
    let pickCount: Int
    /// `Character` offsets in `app.name` to draw at weight 600.
    let highlights: [Int]
    var id: String { app.id }
}

/// What Return (or ⌘↩, ⌘C, ⌘1–⌘5) asked for. The app delegate carries it out.
enum Activation {
    /// `query` is what was typed, `picked` the row's position: anything but 0 teaches the query.
    case launch(AppEntry, query: String, picked: Int, reveal: Bool)
    case copy(display: String, text: String)
}

@MainActor @Observable
final class SearchModel {
    var query = "" { didSet { if query != oldValue { refresh() } } }
    private(set) var tray: Tray = .recent([])
    var selection = 0
    /// Bumped on every show; the view focuses the field.
    var focusRequest = 0
    /// True while an input method is composing, when the completion would only get in the way.
    var isComposing = false
    var index = AppIndex.empty { didSet { refresh() } }
    var usage = UsageStore()
    @ObservationIgnored var onActivate: ((Activation) -> Void)?

    func refresh() {
        let typed = QueryKeys(query)
        let sum = Calculator.evaluate(query)
        if typed.isEmpty {
            // Ask for more than five, since a recent app may have been deleted since.
            tray = .recent(Array(usage.recent(limit: 10).compactMap(index.app(id:)).prefix(5)))
        } else if sum != .notMath {
            tray = .math(expression: Calculator.expressionLine(query), outcome: sum)
        } else {
            let rows = Ranker.rank(typed, index.searchables, usage: usage, now: .now).compactMap { r in
                index.app(id: r.item.id).map { AppRow(app: $0, pickCount: r.pickCount, highlights: r.highlights) }
            }
            tray = rows.isEmpty ? .nothing : .apps(rows)
        }
        selection = 0
    }

    var rowCount: Int {
        switch tray {
        case .recent(let apps): apps.count
        case .apps(let rows): rows.count
        case .math, .nothing: 0
        }
    }

    func move(_ step: Int) {
        guard rowCount > 0 else { return }
        selection = (selection + step + rowCount) % rowCount
    }

    /// Grey text after the caret for the selected row. Tab accepts it.
    var ghost: Ranker.Completion {
        guard !isComposing, case .apps(let rows) = tray, rows.indices.contains(selection) else { return .none }
        return Ranker.completion(typed: query, name: rows[selection].app.name)
    }

    func acceptGhost() {
        switch ghost {
        case .suffix(let rest): query += rest
        case .replace(let name): query = name
        case .none: break
        }
    }

    /// The line under the list: why the top app is first, or what Return is about to teach.
    var why: String? {
        guard case .apps(let rows) = tray, rows.indices.contains(selection) else { return nil }
        let typed = query.trimmingCharacters(in: .whitespaces), row = rows[selection]
        if selection > 0 { return "Opening this teaches “\(typed)” to put \(row.app.name) first." }
        guard row.pickCount > 0 else { return nil }
        let times = row.pickCount == 1 ? "1 time" : "\(row.pickCount) times"
        return "\(row.app.name) is first because you picked it for “\(typed)” \(times)."
    }

    /// Esc: the first clears the field, the second closes. Returns true when it cleared.
    func clear() -> Bool {
        guard !query.isEmpty else { return false }
        query = ""
        return true
    }

    func activateSelection(reveal: Bool = false) {
        switch tray {
        case .math(_, .value(_, let display, let copy)):
            onActivate?(.copy(display: display, text: copy))
        case .recent(let apps) where apps.indices.contains(selection):
            onActivate?(.launch(apps[selection], query: "", picked: selection, reveal: reveal))
        case .apps(let rows) where rows.indices.contains(selection):
            onActivate?(.launch(rows[selection].app, query: query, picked: selection, reveal: reveal))
        default:
            break  // an unfinished sum, an error, or no match: Return does nothing
        }
    }

    /// ⌘1–⌘5 while the field is empty. Returns false when there is no such recent app.
    func openRecent(_ number: Int) -> Bool {
        guard case .recent(let apps) = tray, apps.indices.contains(number - 1) else { return false }
        selection = number - 1
        activateSelection()
        return true
    }

    /// ⌘C copies a sum's result. Returns false when there is no result, so the field gets ⌘C.
    func copyResult() -> Bool {
        guard case .math(_, .value) = tray else { return false }
        activateSelection()
        return true
    }
}
