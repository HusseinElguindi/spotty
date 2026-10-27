import AppKit
import SwiftUI

/// The "B · Quiet" colour tokens from docs/design.md. Each one follows the system appearance.
enum Quiet {
    static let panel = color(dark: hex(0x0D0E10), light: hex(0xF9FAFB))
    static let ink1 = color(dark: hex(0xF7F8F8), light: hex(0x14161B))
    static let ink2 = color(dark: hex(0xC7CBD2), light: hex(0x2F3339))
    static let ink3 = color(dark: hex(0xB3B8C1), light: hex(0x44484E))
    static let ink4 = color(dark: hex(0x9A9FA6), light: hex(0x5D6167))
    static let fillSelected = color(dark: .white.withAlphaComponent(0.10), light: .black.withAlphaComponent(0.06))
    static let ringSelected = color(dark: .white.withAlphaComponent(0.16), light: .black.withAlphaComponent(0.12))
    static let fillQuiet = color(dark: .white.withAlphaComponent(0.08), light: .black.withAlphaComponent(0.06))
    static let wash = color(dark: .white.withAlphaComponent(0.05), light: .black.withAlphaComponent(0.045))
    static let washRing = color(dark: .white.withAlphaComponent(0.07), light: .black.withAlphaComponent(0.07))
    static let plate = color(dark: hex(0x2B2D30), light: hex(0xFBFCFD))
    static let indigo = color(dark: hex(0x7C89F5), light: hex(0x5E6AD2))
    static let accent = color(dark: hex(0xF7F8F8), light: hex(0x14161B))
    static let onAccent = color(dark: hex(0x08090A), light: hex(0xFBFCFD))
    /// The panel's 0.5 pt inner ring.
    static let panelRing = color(dark: .white.withAlphaComponent(0.10), light: .black.withAlphaComponent(0.10))

    private static func color(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    private static func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
