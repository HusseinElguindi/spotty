import AppKit
import SwiftUI

/// The "B · Quiet" colour tokens from docs/design.md, in the Rex palette. Each one follows the system appearance.
enum Quiet {
    static let panel = color(dark: hex(0x1C1C1C), light: hex(0xF6F8FA))
    static let ink1 = color(dark: hex(0xE6EDF3), light: hex(0x1F2328))
    static let ink2 = color(dark: hex(0xC9D1D9), light: hex(0x31363C))
    static let ink3 = color(dark: hex(0xB1BAC4), light: hex(0x424A53))
    static let ink4 = color(dark: hex(0x8B949E), light: hex(0x59636E))
    static let fillSelected = color(dark: .white.withAlphaComponent(0.10), light: .black.withAlphaComponent(0.06))
    static let ringSelected = color(dark: .white.withAlphaComponent(0.16), light: .black.withAlphaComponent(0.12))
    static let fillQuiet = color(dark: .white.withAlphaComponent(0.08), light: .black.withAlphaComponent(0.06))
    static let wash = color(dark: .white.withAlphaComponent(0.05), light: .black.withAlphaComponent(0.045))
    static let washRing = color(dark: .white.withAlphaComponent(0.07), light: .black.withAlphaComponent(0.07))
    static let plate = color(dark: hex(0x2A2A2A), light: hex(0xFFFFFF))
    static let indigo = color(dark: hex(0x58A6FF), light: hex(0x0969DA))
    static let accent = color(dark: hex(0xE6EDF3), light: hex(0x1F2328))
    static let onAccent = color(dark: hex(0x0D1117), light: hex(0xFFFFFF))
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
