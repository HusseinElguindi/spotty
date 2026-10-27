import CoreGraphics

/// Where the launcher sits on its screen, as fractions of the screen's visible area, so a spot
/// picked on one display carries over to displays of other sizes. Pure, so dragging and snapping
/// are tested without AppKit; screen rectangles use AppKit's bottom-left origin.
public struct PanelPlacement: Codable, Equatable, Sendable {
    /// The panel's horizontal centre: 0 at the visible area's left edge, 1 at its right.
    public var centerX: Double
    /// The panel's top edge: 0 at the visible area's top, 1 at its bottom.
    public var top: Double

    public init(centerX: Double, top: Double) {
        self.centerX = centerX
        self.top = top
    }

    /// Centred, with the top edge a third of the way down.
    public static let standard = PanelPlacement(centerX: 0.5, top: 1.0 / 3)

    /// How close a drag must come to a guide, in points, before it sticks to it.
    public static let snapDistance: CGFloat = 12

    /// The guides a drag can stick to: the screen's centre line, and the line the standard
    /// placement's top edge sits on.
    public struct Guides: OptionSet, Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let centerX = Guides(rawValue: 1)
        public static let standardTop = Guides(rawValue: 2)
    }

    /// The panel's centre and top edge in screen points, rounded, and clamped so a panel
    /// `width` wide and up to `tallest` high stays inside `visible`.
    public func resolve(in visible: CGRect, width: CGFloat, tallest: CGFloat) -> (midX: CGFloat, top: CGFloat) {
        let midX = visible.minX + visible.width * centerX
        let top = visible.maxY - visible.height * self.top
        return Self.clamp(midX: midX, top: top, in: visible, width: width, tallest: tallest)
    }

    /// The placement for a panel dragged to `midX` and `top`, stuck to any guide within
    /// `snapDistance`, and which guides it stuck to.
    public static func dragged(midX: CGFloat, top: CGFloat, in visible: CGRect, width: CGFloat,
                               tallest: CGFloat) -> (placement: PanelPlacement, snapped: Guides) {
        guard visible.width > 0, visible.height > 0 else { return (.standard, [.centerX, .standardTop]) }
        let (midX, top) = clamp(midX: midX, top: top, in: visible, width: width, tallest: tallest)
        var placement = PanelPlacement(centerX: Double((midX - visible.minX) / visible.width),
                                       top: Double((visible.maxY - top) / visible.height))
        var snapped: Guides = []
        let standardPoints = standard.resolve(in: visible, width: width, tallest: tallest)
        if abs(midX - standardPoints.midX) <= snapDistance {
            placement.centerX = standard.centerX
            snapped.insert(.centerX)
        }
        if abs(top - standardPoints.top) <= snapDistance {
            placement.top = standard.top
            snapped.insert(.standardTop)
        }
        return (placement, snapped)
    }

    private static func clamp(midX: CGFloat, top: CGFloat, in visible: CGRect, width: CGFloat,
                              tallest: CGFloat) -> (midX: CGFloat, top: CGFloat) {
        func clamp(_ v: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat { low > high ? (low + high) / 2 : min(max(v, low), high) }
        return (clamp(midX, visible.minX + width / 2, visible.maxX - width / 2).rounded(),
                clamp(top, visible.minY + tallest, visible.maxY).rounded())
    }
}
