import XCTest
@testable import Crap4SwiftCore

final class SwiftMethodParserTests: XCTestCase {

    private func source(_ lines: [String]) -> String {
        lines.joined(separator: "\n")
    }

    func testExtractsConcreteMethodsWithLinesAndComplexity() {
        let text = source([
            "import Foundation",
            "",
            "struct Sample {",
            "    func alpha(_ a: Bool, _ b: Bool) -> Int {",
            "        if a && b {",
            "            return 1",
            "        }",
            "        return 0",
            "    }",
            "",
            "    func beta(_ x: Int) -> Int {",
            "        switch x {",
            "        case 1: return 1",
            "        case 2: return 2",
            "        default: return 0",
            "        }",
            "    }",
            "}"
        ])

        let methods = SwiftMethodParser.parse(text)

        XCTAssertEqual(methods, [
            MethodDescriptor(name: "alpha", startLine: 4, endLine: 9, complexity: 3, enclosingType: "Sample"),
            MethodDescriptor(name: "beta", startLine: 11, endLine: 17, complexity: 4, enclosingType: "Sample")
        ])
    }

    func testIgnoresBodylessDeclarationsAndInitializers() {
        let text = source([
            "protocol P {",
            "    func requirement() -> Int",
            "}",
            "",
            "struct Sample {",
            "    init() {",
            "    }",
            "",
            "    func present() -> Int {",
            "        return 1",
            "    }",
            "}"
        ])

        let methods = SwiftMethodParser.parse(text)

        XCTAssertEqual(methods, [
            MethodDescriptor(name: "present", startLine: 9, endLine: 11, complexity: 1, enclosingType: "Sample")
        ])
    }

    func testIgnoresFunctionsDeclaredInsideAnotherFunction() {
        let text = source([
            "struct S {",
            "    func outer() -> Int {",
            "        func inner() -> Int { return 1 }",
            "        if true {",
            "            return inner()",
            "        }",
            "        return 0",
            "    }",
            "}"
        ])

        let methods = SwiftMethodParser.parse(text)

        XCTAssertEqual(methods, [
            MethodDescriptor(name: "outer", startLine: 2, endLine: 8, complexity: 2, enclosingType: "S")
        ])
    }

    func testIgnoresKeywordsInsideCommentsAndStrings() {
        let text = source([
            "struct Sample {",
            "    func stable() -> Int {",
            "        let text = \"if && || ? case catch\"",
            "        // if && || ? case catch",
            "        /* if && || ? case catch */",
            "        return 1",
            "    }",
            "}"
        ])

        let methods = SwiftMethodParser.parse(text)

        XCTAssertEqual(methods, [
            MethodDescriptor(name: "stable", startLine: 2, endLine: 7, complexity: 1, enclosingType: "Sample")
        ])
    }

    func testCountsDecisionNodes() {
        let text = source([
            "struct Sample {",
            "    func score(_ a: Bool, _ values: [Int]) -> Int {",
            "        guard a else { return 0 }",
            "        for value in values {",
            "            if value > 0 {",
            "                return value",
            "            }",
            "        }",
            "        while a {",
            "            break",
            "        }",
            "        let x = a ? 1 : 0",
            "        do {",
            "            return x",
            "        } catch {",
            "            return 1",
            "        }",
            "    }",
            "}"
        ])

        let methods = SwiftMethodParser.parse(text)

        XCTAssertEqual(methods, [
            MethodDescriptor(name: "score", startLine: 2, endLine: 18, complexity: 7, enclosingType: "Sample")
        ])
    }

    func testDoesNotCountOptionalTypeAsTernary() {
        let text = source([
            "struct Sample {",
            "    func coalesce(_ maybe: Int?) -> Int {",
            "        let y = maybe ?? 0",
            "        return y",
            "    }",
            "}"
        ])

        let methods = SwiftMethodParser.parse(text)

        XCTAssertEqual(methods, [
            MethodDescriptor(name: "coalesce", startLine: 2, endLine: 5, complexity: 2, enclosingType: "Sample")
        ])
    }

    func testTracksEnclosingTypeForNestedAndExtendedTypes() {
        let text = source([
            "struct Outer {",
            "    struct Inner {",
            "        func deep() -> Int {",
            "            return 1",
            "        }",
            "    }",
            "}",
            "",
            "extension Array {",
            "    func second() -> Element? {",
            "        return nil",
            "    }",
            "}"
        ])

        let methods = SwiftMethodParser.parse(text)

        XCTAssertEqual(methods, [
            MethodDescriptor(name: "deep", startLine: 3, endLine: 5, complexity: 1, enclosingType: "Inner"),
            MethodDescriptor(name: "second", startLine: 10, endLine: 12, complexity: 1, enclosingType: "Array")
        ])
    }

    func testDoesNotTreatClassModifierAsType() {
        let text = source([
            "class Sample {",
            "    class func factory() -> Int {",
            "        return 1",
            "    }",
            "}"
        ])

        let methods = SwiftMethodParser.parse(text)

        XCTAssertEqual(methods, [
            MethodDescriptor(name: "factory", startLine: 2, endLine: 4, complexity: 1, enclosingType: "Sample")
        ])
    }
}
