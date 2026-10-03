import XCTest
@testable import Crap4SwiftCore

final class CrapAnalyzerTests: XCTestCase {

    private func exportJSON(path: String, functions: [(name: String, startLine: Int, regions: [[Int]])]) -> String {
        let encoded = functions.map { function -> String in
            let regions = function.regions.map { "[" + $0.map(String.init).joined(separator: ",") + "]" }
            return """
            {"name":"\(function.name)","count":1,"filenames":["\(path)"],"regions":[\(regions.joined(separator: ","))]}
            """
        }
        return """
        {"data":[{"files":[],"functions":[\(encoded.joined(separator: ","))]}],"type":"llvm.coverage.json.export","version":"3.0.1"}
        """
    }

    func testComputesScoresAndSortsByCrapWithNullsLast() throws {
        let root = try TempDir.make()
        let source = root.appendingPathComponent("Sources/App/Sample.swift")
        try TempDir.write([
            "struct Sample {",
            "    func alpha(_ a: Bool) -> Int {",
            "        if a {",
            "            return 1",
            "        }",
            "        return 0",
            "    }",
            "",
            "    func beta() -> Int {",
            "        return 1",
            "    }",
            "",
            "    func gamma() -> Int {",
            "        return 2",
            "    }",
            "}"
        ].joined(separator: "\n"), to: source)

        let json = root.appendingPathComponent("coverage.json")
        try TempDir.write(exportJSON(path: source.path, functions: [
            (name: "$s5alpha", startLine: 2, regions: [[2, 1, 7, 1, 1, 0, 0, 0]]),
            (name: "$s4beta", startLine: 9, regions: [[9, 1, 11, 1, 0, 0, 0, 0]])
        ]), to: json)

        let metrics = try CrapAnalyzer.analyze(projectRoot: root, files: [source], coverageJSON: json)

        XCTAssertEqual(metrics.map(\.methodName), ["alpha", "beta", "gamma"])

        XCTAssertEqual(metrics[0].className, "Sample")
        XCTAssertEqual(metrics[0].complexity, 2)
        XCTAssertEqual(metrics[0].coveragePercent!, 100.0, accuracy: 0.001)
        XCTAssertEqual(metrics[0].crapScore!, 2.0, accuracy: 0.0001)

        XCTAssertEqual(metrics[1].complexity, 1)
        XCTAssertEqual(metrics[1].coveragePercent!, 0.0, accuracy: 0.001)
        XCTAssertEqual(metrics[1].crapScore!, 2.0, accuracy: 0.0001)

        XCTAssertNil(metrics[2].coveragePercent)
        XCTAssertNil(metrics[2].crapScore)
    }

    func testClassNameFromSource() {
        XCTAssertEqual(
            CrapAnalyzer.classNameFromSource(file: URL(fileURLWithPath: "/tmp/Sources/Sample.swift"), source: ""),
            "Sample"
        )
    }

    func testLookupCoveragePrefersExactThenNearestWithinSpan() {
        let path = "/tmp/Sources/Sample.swift"
        let coverage: [String: CoverageData] = [
            "\(path)#10": CoverageData(missedRegions: 1, coveredRegions: 3),
            "\(path)#15": CoverageData(missedRegions: 0, coveredRegions: 8)
        ]

        XCTAssertEqual(CrapAnalyzer.lookupCoverage(coverage, path: path, startLine: 10, endLine: 15)!, 75.0, accuracy: 0.001)
        XCTAssertEqual(CrapAnalyzer.lookupCoverage(coverage, path: path, startLine: 13, endLine: 15)!, 100.0, accuracy: 0.001)
        XCTAssertNil(CrapAnalyzer.lookupCoverage(coverage, path: path, startLine: 40, endLine: 45))
        XCTAssertNil(CrapAnalyzer.lookupCoverage([:], path: path, startLine: 1, endLine: 2))
    }

    func testParseTrailingLine() {
        XCTAssertEqual(CrapAnalyzer.parseTrailingLine("/tmp/S.swift#10", prefixLength: "/tmp/S.swift#".count), 10)
        XCTAssertEqual(CrapAnalyzer.parseTrailingLine("/tmp/S.swift#oops", prefixLength: "/tmp/S.swift#".count), Int.max)
        XCTAssertEqual(CrapAnalyzer.parseTrailingLine("/tmp/S.swift#", prefixLength: "/tmp/S.swift#".count), Int.max)
    }
}
