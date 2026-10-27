/// What a key press in the panel means. Pure, so the decision is tested without AppKit; the app
/// passes in the event's key code, whether ⌘ alone is held, and its characters.
public enum PanelKey: Equatable, Sendable {
    case moveDown, moveUp, acceptCompletion
    /// Esc with text in the field.
    case clear
    /// Esc on an empty field.
    case close
    case activate(reveal: Bool)
    /// ⌘C: copies a sum's result, otherwise left to the field.
    case copy
    /// ⌘1–⌘5 on an empty field.
    case openRecent(Int)
    /// Not ours: the field gets it.
    case pass

    public static func decide(keyCode: Int, commandOnly: Bool, characters: String?, queryIsEmpty: Bool) -> PanelKey {
        switch keyCode {
        case 125: return .moveDown
        case 126: return .moveUp
        case 48: return .acceptCompletion
        // Whatever modifiers are still held: pressing Esc while ⌘ from ⌘Space is still down
        // arrives as ⌘Esc and must close all the same.
        case 53: return queryIsEmpty ? .close : .clear
        case 36, 76: return .activate(reveal: commandOnly)
        default: break
        }
        guard commandOnly, let key = characters else { return .pass }
        if key == "c" { return .copy }
        if queryIsEmpty, let n = Int(key), (1...5).contains(n) { return .openRecent(n) }
        return .pass
    }
}
