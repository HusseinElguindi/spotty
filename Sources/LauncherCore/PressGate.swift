/// Lets a held shortcut act once: a press counts only after the previous one was released, so
/// key repeat while it is held does nothing, while two real taps, however fast, both count.
public struct PressGate: Sendable, Equatable {
    public private(set) var isDown = false

    public init() {}

    /// A press arrived. True when it should act.
    public mutating func press() -> Bool {
        defer { isDown = true }
        return !isDown
    }

    public mutating func release() {
        isDown = false
    }
}
