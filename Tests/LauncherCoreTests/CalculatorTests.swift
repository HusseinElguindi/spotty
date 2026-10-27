import Foundation
import XCTest
@testable import LauncherCore

final class CalculatorTests: XCTestCase {
    func display(_ input: String) -> String? {
        if case .value(_, let display, _) = Calculator.evaluate(input) { return display }
        return nil
    }

    func testResults() {
        let cases: [(String, String)] = [
            ("2+2", "4"), ("0.1 + 0.2", "0.3"), ("1/3", "0.333333333333"), ("2/3", "0.666666666667"),
            ("2 + 3 * 4", "14"), ("(2 + 3) * 4", "20"), ("2^10", "1,024"), ("2^3^2", "512"),
            ("-2^2", "−4"), ("2^-1", "0.5"), ("(2+3", "5"), ("((1+2)*(3", "9"),
            ("1,234.5 * 2", "2,469"), ("1e3 + 1", "1,001"), ("2.5e-3 * 4", "0.01"),
            ("50%", "0.5"), ("200 + 10%", "220"), ("200 - 10%", "180"), ("200 * 10%", "20"),
            ("sqrt 16 + 9", "13"), ("sqrt(2)", "1.41421356237"), ("√9", "3"), ("2pi", "6.28318530718"),
            ("3(4+5)", "27"), ("2 sqrt 9", "6"), ("10 mod 3", "1"), ("-10 mod 3", "2"),
            ("floor(-2.5)", "−3"), ("ceil(2.1)", "3"), ("round(2.5)", "3"), ("abs(-4)", "4"),
            ("ln(e)", "1"), ("log(1000)", "3"), ("2x3", "6"), ("12 × 3 ÷ 4", "9"), ("7 − 10", "−3"),
            ("1.1^2", "1.21"), ("4^0.5", "2"), ("10^20", "1e20"), ("1/10^9", "1e−9"),
            ("123456789 * 1000", "123,456,789,000"), ("-5", "−5"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(display(input), expected, "input \"\(input)\"")
        }
    }

    func copy(_ input: String) -> String? {
        if case .value(_, _, let copy) = Calculator.evaluate(input) { return copy }
        return nil
    }

    func testCopyTextIsPlainASCII() {
        XCTAssertEqual(copy("1234.5 * 1000"), "1234500")
        XCTAssertEqual(copy("7 - 10"), "-3", "a hyphen, so other apps can parse it")
        XCTAssertEqual(copy("1/10^9"), "1e-9")
        XCTAssertEqual(copy("10^20"), "1e20")
    }

    func testTrigonometryInRadians() {
        let cases: [(String, String)] = [
            ("sin(0)", "0"), ("sin(pi/2)", "1"), ("sin(pi)", "0"), ("cos(pi)", "−1"), ("cos(pi/3)", "0.5"),
            ("tan(pi/4)", "1"), ("sin 1", "0.841470984808"), ("2 sin(pi/6)", "1"),
            ("asin(1)", "1.57079632679"), ("acos(0)", "1.57079632679"), ("atan(1)*4", "3.14159265359"),
            ("sinh(0)", "0"), ("cosh(0)", "1"), ("tanh(0)", "0"), ("cosh(1)", "1.54308063482"),
            ("asinh(0)", "0"), ("acosh(1)", "0"), ("atanh(0.5)", "0.549306144334"), ("exp(1)", "2.71828182846"),
            ("SIN(PI)", "0"),
        ]
        for (input, expected) in cases {
            guard case .value(_, let display, _) = Calculator.evaluate(input) else {
                XCTFail("\(input) is not a value: \(Calculator.evaluate(input))"); continue
            }
            XCTAssertEqual(display, expected, input)
        }
        XCTAssertEqual(Calculator.evaluate("asin(2)"), .error(.notReal))
        XCTAssertEqual(Calculator.evaluate("acosh(0)"), .error(.notReal))
        XCTAssertEqual(Calculator.evaluate("atanh(1)"), .error(.notReal))
        // A function name alone is still a word, so app search carries on.
        for word in ["sin", "cos", "cosh", "tan", "exp"] { XCTAssertEqual(Calculator.evaluate(word), .notMath, word) }
        XCTAssertEqual(Calculator.expressionLine("2sin(pi/6)"), "2 sin(π ÷ 6)")
    }

    func testNotMath() {
        for input in ["safari", "1password", "2", "e", "pi", "sq", "", "  ", "1,2", "2+)", "3 4", "hello + 2", "mod 3"] {
            XCTAssertEqual(Calculator.evaluate(input), .notMath, "input \"\(input)\"")
        }
    }

    func testIncompleteShowsTheValueSoFar() {
        let cases: [(String, String?)] = [
            ("1299*1.13+", "1,467.87"), ("12*", "12"), ("(3+", "3"), ("2^", "2"),
            ("2*sqrt(", "2"), ("(1+2)*(", "3"), ("10 - 20 *", "−10"), ("-", nil),
        ]
        for (input, soFar) in cases {
            XCTAssertEqual(Calculator.evaluate(input), .incomplete(soFar: soFar), "input \"\(input)\"")
        }
        XCTAssertEqual(Calculator.evaluate("sqrt"), .notMath, "a function name alone is still just a word")
    }

    func testExpressionLine() {
        let cases: [(String, String)] = [
            ("1299*1.13", "1,299 × 1.13"), ("1299*1.13+", "1,299 × 1.13 +"), ("-2^2-sqrt 9", "−2^2 − √9"),
            ("1.50+2", "1.50 + 2"), ("200 + 10%", "200 + 10%"), ("2pi", "2π"), ("3(4+5)", "3(4 + 5)"),
            ("12 x 3", "12 × 3"), ("1,234.5/2", "1,234.5 ÷ 2"), ("ln 5", "ln 5"), ("1e6*2", "1e6 × 2"),
            ("10 mod 3", "10 mod 3"), ("2 ln(5)", "2 ln(5)"), ("5--2", "5 − −2"),
        ]
        for (input, line) in cases {
            XCTAssertEqual(Calculator.expressionLine(input), line, "input \"\(input)\"")
        }
    }

    func testErrors() {
        XCTAssertEqual(Calculator.evaluate("1/0"), .error(.divideByZero))
        XCTAssertEqual(Calculator.evaluate("5 mod 0"), .error(.divideByZero))
        XCTAssertEqual(Calculator.evaluate("sqrt(-1)"), .error(.notReal))
        XCTAssertEqual(Calculator.evaluate("ln(0)"), .error(.notReal))
        XCTAssertEqual(Calculator.evaluate("(-8)^(1/3)"), .error(.notReal))
        XCTAssertEqual(Calculator.evaluate("10^200 * 10^200"), .error(.tooLarge))
    }

    func testPrecedenceTree() throws {
        let expr = try Parser.parse(lex("1 + 2 * 3^2")!)
        XCTAssertEqual(expr, .binary("+", .number(1), .binary("*", .number(2), .binary("^", .number(3), .number(2)))))
    }
}
