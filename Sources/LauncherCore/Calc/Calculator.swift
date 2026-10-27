import Foundation

public enum CalcOutcome: Equatable, Sendable {
    /// The text isn't math ("safari", "1password", "2"). Show only apps.
    case notMath
    /// Math that is still being typed ("1299*1.13+"). `soFar` is the value of the finished part
    /// ("1,467.87"), shown in ink-3 under "So far"; nil when there's nothing yet ("-").
    case incomplete(soFar: String?)
    /// A result: `display` for the hero number ("1,467.87", "−3"), `copy` for the clipboard ("1467.87", "-3").
    case value(Decimal, display: String, copy: String)
    /// Math that can't be computed ("1/0").
    case error(CalcError)
}

public enum Calculator {
    public static func evaluate(_ input: String) -> CalcOutcome {
        guard let tokens = lex(input), !tokens.isEmpty else { return .notMath }
        let expr: Expr
        do {
            expr = try Parser.parse(tokens)
        } catch .incomplete {
            // Only call it "incomplete" once there is an operator; "sqrt" alone is still a word.
            guard tokens.contains(where: { if case .op = $0 { true } else { false } }) else { return .notMath }
            return .incomplete(soFar: valueSoFar(tokens))
        } catch {
            return .notMath
        }
        guard expr.hasOperation else { return .notMath }
        do {
            let value = try Evaluator.evaluate(expr)
            return .value(value, display: CalcFormatter.display(value), copy: CalcFormatter.copyText(value))
        } catch {
            return .error(error)
        }
    }

    /// Drops what is still waiting for an operand (operators, "(", a function name) from the end
    /// and evaluates the rest: "1299*1.13+" is 1,467.87 so far. Open brackets close themselves.
    static func valueSoFar(_ tokens: [Token]) -> String? {
        var tokens = tokens
        while let last = tokens.last, last.awaitsOperand { tokens.removeLast() }
        guard !tokens.isEmpty,
              let expr = try? Parser.parse(tokens),
              let value = try? Evaluator.evaluate(expr)
        else { return nil }
        return CalcFormatter.display(value)
    }

    /// The sum tidied for the line above the result: "1299*1.13" reads "1,299 × 1.13" and
    /// "-2^2-sqrt 9" reads "−2^2 − √9". Digits stay as typed apart from the grouping commas.
    public static func expressionLine(_ input: String) -> String {
        guard let tokens = lexSpelled(input) else { return input }
        var out = ""
        var previous: Token?
        for (token, text) in tokens {
            let afterOperand = previous?.isOperand == true || previous == .op("%")
            let afterFunction = if case .name(let n)? = previous, CalcFunction(rawValue: n) != nil, n != "sqrt" { true } else { false }
            switch token {
            case .number:
                if afterFunction { out += " " }
                let parts = text.split(separator: "e", maxSplits: 1, omittingEmptySubsequences: false)
                out += CalcFormatter.grouped(String(parts[0])) + (parts.count > 1 ? "e" + parts[1] : "")
            case .op("-") where !afterOperand:
                out += "\u{2212}"
            case .op("+") where !afterOperand:
                out += "+"
            case .op(let op):
                switch op {
                case "%", "^": out.append(op)
                case "*": out += " \u{00D7} "
                case "/": out += " \u{00F7} "
                case "-": out += " \u{2212} "
                default: out += " \(op) "
                }
            case .lparen:
                out += "("
            case .rparen:
                out += ")"
            case .name("mod"):
                out += " mod "
            case .name("sqrt"):
                out += "\u{221A}"
            case .name(let n):
                if constants[n] != nil {
                    if afterFunction { out += " " }
                    out += n == "pi" ? "\u{03C0}" : n
                } else {
                    if afterOperand { out += " " }
                    out += n
                }
            }
            previous = token
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}

extension Token {
    /// Still needs something after it before it means anything: "+", "(", "sqrt", "mod".
    var awaitsOperand: Bool {
        switch self {
        case .op(let op): op != "%"
        case .lparen: true
        case .name(let n): constants[n] == nil
        case .number, .rparen: false
        }
    }
}
