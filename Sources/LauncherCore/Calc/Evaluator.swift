import Foundation

public enum CalcError: Error, Equatable, Sendable {
    case divideByZero, notReal, tooLarge, undefined

    public var message: String {
        switch self {
        case .divideByZero: "Can't divide by zero"
        case .notReal: "Not a real number"
        case .tooLarge: "Number too large"
        case .undefined: "Undefined"
        }
    }
}

/// Evaluates in `Decimal` (base 10, 38 significant digits), so 0.1 + 0.2 is exactly 0.3.
/// Square roots, logarithms and fractional powers go through `Double` and come back.
enum Evaluator {
    static func evaluate(_ expr: Expr) throws(CalcError) -> Decimal {
        let value = try eval(expr)
        guard !value.isNaN else { throw .tooLarge }
        return value
    }

    private static func eval(_ expr: Expr) throws(CalcError) -> Decimal {
        switch expr {
        case .number(let v):
            return v
        case .constant(let name):
            return constants[name]!
        case .negate(let e):
            return -(try eval(e))
        case .percent(let e):
            return try eval(e) / 100
        case .degrees(let e):
            return try eval(e) * constants["pi"]! / 180
        case .binary(let op, let l, .percent(let p)) where op == "+" || op == "-":
            // "200 + 10%" adds 10% of 200, like a handheld calculator.
            let base = try eval(l), share = base * (try eval(p)) / 100
            return op == "+" ? base + share : base - share
        case .binary(let op, let l, let r):
            return try binary(op, try eval(l), try eval(r))
        case .call(let fn, let arg):
            return try call(fn, try eval(arg))
        }
    }

    private static func binary(_ op: Character, _ a: Decimal, _ b: Decimal) throws(CalcError) -> Decimal {
        let result: Decimal
        switch op {
        case "+": result = a + b
        case "-": result = a - b
        case "*": result = a * b
        case "/":
            guard !b.isZero else { throw .divideByZero }
            result = a / b
        case "m":
            guard !b.isZero else { throw .divideByZero }
            result = a - b * rounded(a / b, .down)
        case "^":
            result = try power(a, b)
        default:
            preconditionFailure("unknown operator \(op)")
        }
        guard !result.isNaN else { throw .tooLarge }
        return result
    }

    private static func power(_ base: Decimal, _ exponent: Decimal) throws(CalcError) -> Decimal {
        // Whole exponents stay exact: 2^10, 1.1^3, 10^-2.
        if exponent == rounded(exponent, .plain), Swift.abs(exponent) <= 10_000 {
            let n = NSDecimalNumber(decimal: Swift.abs(exponent)).intValue
            if base.isZero && exponent < 0 { throw .divideByZero }
            let raised = pow(base, n)
            return exponent < 0 ? 1 / raised : raised
        }
        guard base >= 0 else { throw .notReal }  // (-8)^(1/3) has no real answer here
        return try viaDouble(Foundation.pow(double(base), double(exponent)))
    }

    private static func call(_ fn: CalcFunction, _ x: Decimal) throws(CalcError) -> Decimal {
        switch fn {
        case .abs: return Swift.abs(x)
        case .round: return rounded(x, .plain)
        case .floor: return rounded(x, .down)
        case .ceil: return rounded(x, .up)
        case .sqrt:
            guard x >= 0 else { throw .notReal }
            return try viaDouble(Foundation.sqrt(double(x)))
        case .ln:
            guard x > 0 else { throw .notReal }
            return try viaDouble(Foundation.log(double(x)))
        case .log:
            guard x > 0 else { throw .notReal }
            return try viaDouble(Foundation.log10(double(x)))
        case .exp: return try viaDouble(Foundation.exp(double(x)))
        case .sin: return try trig(Foundation.sin(double(x)))
        case .cos: return try trig(Foundation.cos(double(x)))
        case .tan:
            // tan 90° has no value; in binary cos(π/2) is 6e−17, not 0, so catch it by size.
            guard Swift.abs(Foundation.cos(double(x))) > 1e-15 else { throw .undefined }
            return try trig(Foundation.tan(double(x)))
        case .asin:
            guard Swift.abs(x) <= 1 else { throw .notReal }
            return try trig(Foundation.asin(double(x)))
        case .acos:
            guard Swift.abs(x) <= 1 else { throw .notReal }
            return try trig(Foundation.acos(double(x)))
        case .atan: return try trig(Foundation.atan(double(x)))
        case .sinh: return try trig(Foundation.sinh(double(x)))
        case .cosh: return try trig(Foundation.cosh(double(x)))
        case .tanh: return try trig(Foundation.tanh(double(x)))
        case .asinh: return try trig(Foundation.asinh(double(x)))
        case .acosh:
            guard x >= 1 else { throw .notReal }
            return try trig(Foundation.acosh(double(x)))
        case .atanh:
            guard Swift.abs(x) <= 1 else { throw .notReal }
            guard Swift.abs(x) < 1 else { throw .undefined }
            return try trig(Foundation.atanh(double(x)))
        }
    }

    /// Trigonometric and hyperbolic results go through `Double`, whose last digits are noise
    /// for angles like π/6 (sin 30° is 0.49999999999999994). Rounding to 15 significant digits
    /// removes that, and anything within 1e−12 of zero is the zero you meant (sin π is 1.2e−16).
    private static func trig(_ d: Double) throws(CalcError) -> Decimal {
        guard d.isFinite else { return try viaDouble(d) }
        guard Swift.abs(d) >= 1e-12 else { return 0 }
        return try viaDouble(Double(String(format: "%.15g", d)) ?? d)
    }

    /// Rounds to a whole number. `.down` and `.up` go toward minus and plus infinity.
    static func rounded(_ x: Decimal, _ mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var input = x, output = Decimal()
        NSDecimalRound(&output, &input, 0, mode)
        return output
    }

    static func double(_ x: Decimal) -> Double { NSDecimalNumber(decimal: x).doubleValue }

    /// Goes through Swift's shortest round-trip text ("1.4142135623730951") rather than
    /// `Decimal(Double)`, which can drag in binary noise digits.
    static func viaDouble(_ d: Double) throws(CalcError) -> Decimal {
        guard d.isFinite else { throw d.isNaN ? .notReal : .tooLarge }
        guard let value = Decimal(string: "\(d)") else { throw .tooLarge }
        return value
    }
}
