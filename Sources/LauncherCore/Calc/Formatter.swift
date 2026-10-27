import Foundation

/// Formats results by hand rather than with `NumberFormatter`, so output doesn't depend on
/// the Mac's region settings or on Foundation version differences.
public enum CalcFormatter {
    public static let significantDigits = 12

    /// "1,234,567.89", or "1.23456789012e20" outside 1e-6 ..< 1e15, with a true minus sign
    /// ("−3", "1e−9") as the design draws it.
    public static func display(_ value: Decimal) -> String {
        let text = scientific(value) ?? grouped(plain(roundedSignificant(value, significantDigits)))
        return text.replacingOccurrences(of: "-", with: "\u{2212}")
    }

    /// What ⌘C and Return copy: plain ASCII digits that other apps can paste and parse,
    /// no grouping, same rounding as the display.
    public static func copyText(_ value: Decimal) -> String {
        scientific(value) ?? plain(roundedSignificant(value, significantDigits))
    }

    /// "1.5e20" for values outside 1e-6 ..< 1e15, nil for everything shown positionally.
    static func scientific(_ value: Decimal) -> String? {
        let v = roundedSignificant(value, significantDigits)
        guard !v.isZero else { return nil }
        let magnitude = exponent10(v)
        guard magnitude >= 15 || magnitude < -6 else { return nil }
        let mantissa = roundedSignificant(v / pow(10, magnitude), significantDigits)
        return "\(plain(mantissa))e\(magnitude)"
    }

    /// Power of ten of the leading digit: 1234 -> 3, 0.05 -> -2.
    static func exponent10(_ v: Decimal) -> Int {
        let a = Swift.abs(v)
        var e = Int(Foundation.floor(Foundation.log10(NSDecimalNumber(decimal: a).doubleValue)))
        // The Double estimate can be one off near powers of ten; correct it exactly.
        while a >= pow(10, e + 1) { e += 1 }
        while a < pow(10, e) { e -= 1 }
        return e
    }

    static func pow(_ base: Decimal, _ e: Int) -> Decimal {
        e >= 0 ? Foundation.pow(base, e) : 1 / Foundation.pow(base, -e)
    }

    static func roundedSignificant(_ v: Decimal, _ digits: Int) -> Decimal {
        guard !v.isZero else { return 0 }
        var input = v, output = Decimal()
        NSDecimalRound(&output, &input, digits - 1 - exponent10(v), .plain)
        return output
    }

    /// Plain positional digits with no exponent and no trailing zeros: "1234.5", "-0.001".
    static func plain(_ v: Decimal) -> String {
        var s = "\(v)"
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }

    static func grouped(_ s: String) -> String {
        let negative = s.hasPrefix("-")
        let body = negative ? String(s.dropFirst()) : s
        // Keeps a trailing "." while you type "1." and a leading one in ".5".
        let parts = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        var whole = String(parts[0])
        var groups: [String] = []
        while whole.count > 3 {
            groups.insert(String(whole.suffix(3)), at: 0)
            whole.removeLast(3)
        }
        groups.insert(whole, at: 0)
        let fraction = parts.count > 1 ? "." + parts[1] : ""
        return (negative ? "-" : "") + groups.joined(separator: ",") + fraction
    }
}
