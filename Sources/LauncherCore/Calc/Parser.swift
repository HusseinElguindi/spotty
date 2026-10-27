import Foundation

indirect enum Expr: Equatable {
    case number(Decimal)
    case constant(String)
    case negate(Expr)
    case binary(Character, Expr, Expr)  // + - * / ^ and "m" for mod
    case percent(Expr)
    /// "30°" or "30 deg": the angle in radians.
    case degrees(Expr)
    case call(CalcFunction, Expr)

    /// Whether the input did any math. A bare number or constant doesn't, so typing "2"
    /// or "e" never puts a math row above your apps.
    var hasOperation: Bool {
        switch self {
        case .number, .constant: false
        case .negate, .binary, .percent, .degrees, .call: true
        }
    }
}

enum ParseError: Error, Equatable {
    /// Input stopped where an operand was needed: "12*", "(3+". Still being typed.
    case incomplete
    /// Something is in the wrong place: "2+)", "3 4".
    case invalid
}

/// A Pratt parser: each operator has a binding power, and a loop keeps extending the
/// left-hand side while the next operator binds tighter than the caller's minimum.
struct Parser {
    // Binding powers. Higher binds tighter.
    static let additive = 10, multiplicative = 20, unary = 30, function = 35, power = 40, postfix = 50

    private let tokens: [Token]
    private var pos = 0

    init(_ tokens: [Token]) { self.tokens = tokens }

    static func parse(_ tokens: [Token]) throws(ParseError) -> Expr {
        var parser = Parser(tokens)
        let expr = try parser.expression(0)
        guard parser.pos == tokens.count else { throw .invalid }
        return expr
    }

    private var next: Token? { pos < tokens.count ? tokens[pos] : nil }

    private mutating func expression(_ minPower: Int) throws(ParseError) -> Expr {
        var lhs = try prefix()
        while let token = next {
            switch token {
            case .op("%"):
                guard Self.postfix >= minPower else { return lhs }
                pos += 1
                lhs = .percent(lhs)
            case .op("°"):
                guard Self.postfix >= minPower else { return lhs }
                pos += 1
                lhs = .degrees(lhs)
            case .op(let op):
                let (left, right) = Self.infixPowers(op)
                guard left >= minPower else { return lhs }
                pos += 1
                lhs = .binary(op, lhs, try expression(right))
            case .name("mod"):
                guard Self.multiplicative >= minPower else { return lhs }
                pos += 1
                lhs = .binary("m", lhs, try expression(Self.multiplicative + 1))
            case .name, .lparen:
                // Implicit multiplication: "2pi", "3(4+5)", "2 sqrt 9". Never between two plain numbers.
                guard Self.multiplicative >= minPower else { return lhs }
                lhs = .binary("*", lhs, try expression(Self.multiplicative + 1))
            case .number, .rparen:
                return lhs
            }
        }
        return lhs
    }

    private mutating func prefix() throws(ParseError) -> Expr {
        guard let token = next else { throw .incomplete }
        pos += 1
        switch token {
        case .number(let value):
            return .number(value)
        case .name(let name):
            if constants[name] != nil { return .constant(name) }
            guard let fn = CalcFunction(rawValue: name) else { throw .invalid }  // "mod" with no left side
            return .call(fn, try expression(Self.function))
        case .op("-"):
            return .negate(try expression(Self.unary))
        case .op("+"):
            return try expression(Self.unary)
        case .lparen:
            let inner = try expression(0)
            if next == .rparen {
                pos += 1
            } else if next != nil {
                throw .invalid
            }  // at the end of input a missing ")" is filled in: "(2+3" is 5
            return inner
        case .op, .rparen:
            throw .invalid
        }
    }

    /// Left-associative operators bind their right side one step tighter; `^` is right-associative.
    private static func infixPowers(_ op: Character) -> (Int, Int) {
        switch op {
        case "+", "-": (additive, additive + 1)
        case "^": (power, power)
        default: (multiplicative, multiplicative + 1)
        }
    }
}
