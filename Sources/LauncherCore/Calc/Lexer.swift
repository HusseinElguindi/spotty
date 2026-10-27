import Foundation

enum Token: Equatable {
    case number(Decimal)
    case op(Character)  // + - * / ^ %
    case lparen, rparen
    case name(String)   // a known function, constant, or `mod`
}

enum CalcFunction: String, CaseIterable {
    case sqrt, abs, round, floor, ceil, ln, log, exp
    // Trigonometry, in radians.
    case sin, cos, tan, asin, acos, atan
    case sinh, cosh, tanh, asinh, acosh, atanh
}

let constants: [String: Decimal] = [
    "pi": Decimal(string: "3.14159265358979323846264338327950288")!,
    "π": Decimal(string: "3.14159265358979323846264338327950288")!,
    "e": Decimal(string: "2.71828182845904523536028747135266250")!,
]

/// Turns input into tokens, or returns nil when the text can't be math at all
/// (an unknown word, a stray symbol). nil means "not math", so the panel shows only apps.
func lex(_ input: String) -> [Token]? {
    lexSpelled(input)?.map(\.token)
}

/// The same tokens, each with the text it was typed as, so the expression line above the
/// result can keep "1.50" as typed instead of reprinting it as "1.5".
func lexSpelled(_ input: String) -> [(token: Token, text: String)]? {
    let chars = Array(input)
    var tokens: [(token: Token, text: String)] = []
    var i = 0

    func isDigit(_ k: Int) -> Bool { k < chars.count && chars[k].isASCII && chars[k].isNumber }

    while i < chars.count {
        let c = chars[i]
        if c.isWhitespace { i += 1; continue }

        if isDigit(i) || (c == "." && isDigit(i + 1)) {
            var text = ""
            while i < chars.count {
                if isDigit(i) || chars[i] == "." {
                    text.append(chars[i]); i += 1
                } else if chars[i] == ",", isDigit(i + 1), isDigit(i + 2), isDigit(i + 3), !isDigit(i + 4) {
                    i += 1  // thousands separator: "1,234"
                } else {
                    break
                }
            }
            // Exponent: "1e6", "2.5e-3". A bare "e" after a number is Euler's number instead.
            if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                var j = i + 1
                var exp = "e"
                if j < chars.count, chars[j] == "+" || chars[j] == "-" { exp.append(chars[j]); j += 1 }
                if isDigit(j) {
                    while isDigit(j) { exp.append(chars[j]); j += 1 }
                    text += exp
                    i = j
                }
            }
            guard text.filter({ $0 == "." }).count <= 1, let value = Decimal(string: text) else { return nil }
            tokens.append((.number(value), text))
            continue
        }

        // "2x3" means 2 × 3 when x sits between a number (or ")") and a digit.
        if c == "x" || c == "X", let last = tokens.last?.token, last.isOperand,
           let next = chars[(i + 1)...].first(where: { !$0.isWhitespace }), next.isNumber || next == "(" || next == "." {
            tokens.append((.op("*"), "x")); i += 1; continue
        }

        if c.isLetter {
            var word = ""
            while i < chars.count, chars[i].isLetter { word.append(chars[i]); i += 1 }
            let lower = word.lowercased()
            if lower == "deg" { tokens.append((.op("°"), word)); continue }  // "30 deg" is 30°
            guard constants[lower] != nil || CalcFunction(rawValue: lower) != nil || lower == "mod" else { return nil }
            tokens.append((.name(lower), word))
            continue
        }

        let token: Token
        switch c {
        case "+": token = .op("+")
        case "-", "\u{2212}": token = .op("-")
        case "*", "\u{00D7}", "\u{00B7}": token = .op("*")
        case "/", "\u{00F7}": token = .op("/")
        case "^": token = .op("^")
        case "%": token = .op("%")
        case "\u{00B0}": token = .op("°")  // degrees: 30° is 30 × π/180
        case "(": token = .lparen
        case ")": token = .rparen
        case "\u{221A}": token = .name("sqrt")  // √
        default: return nil
        }
        tokens.append((token, String(c)))
        i += 1
    }
    return tokens
}

extension Token {
    /// Ends an operand, so what follows is in operator position.
    var isOperand: Bool {
        switch self {
        case .number, .rparen: true
        case .name(let n): constants[n] != nil
        default: false
        }
    }
}
