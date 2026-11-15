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

        let metrics = try CrapAnalyzer.analyze(projectRoot: root, files: [source], coverageJSON: json).metrics

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

    func testModuleNameIsThePathComponentAfterSources() {
        XCTAssertEqual(CrapAnalyzer.moduleName(ofPath: "/repo/AppPackages/Features/Sources/Library/SearchModel.swift"), "Library")
        XCTAssertNil(CrapAnalyzer.moduleName(ofPath: "/repo/AppPackages/Features/Tests/LibraryTests/SearchModelTests.swift"))
        XCTAssertNil(CrapAnalyzer.moduleName(ofPath: "/repo/Sources/Stray.swift"))
    }

    /// A module with code and no record of it at all: its methods score nil, and a nil score is
    /// never compared with the threshold. That is reported, because the tool cannot tell a broken
    /// report from code no test binary links — `Mocks` (`#if DEBUG`) and `ServiceProtocols` (an
    /// uncalled extension) are both legitimately absent from their package's export.
    func testReportsAModuleThatContributesNoCoverage() throws {
        let root = try TempDir.make()
        let source = root.appendingPathComponent("Sources/Library/SearchModel.swift")
        try TempDir.write([
            "struct SearchModel {",
            "    func name(_ a: Bool) -> String {",
            "        if a {",
            "            return \"C\"",
            "        }",
            "        return \"\"",
            "    }",
            "}"
        ].joined(separator: "\n"), to: source)

        // A second module the report does carry, so the run is otherwise healthy — the shape of a
        // real package whose `Mocks` target nothing links.
        let measured = root.appendingPathComponent("Sources/Design/Strings.swift")
        try TempDir.write([
            "struct Strings {",
            "    func alpha() -> Int {",
            "        return 1",
            "    }",
            "}"
        ].joined(separator: "\n"), to: measured)

        let json = root.appendingPathComponent("coverage.json")
        try TempDir.write(exportJSON(path: measured.path, functions: [
            (name: "$s5alpha", startLine: 2, regions: [[2, 1, 3, 1, 1, 0, 0, 0]])
        ]), to: json)

        let result = try CrapAnalyzer.analyze(
            projectRoot: root,
            files: [source, measured],
            coverageJSON: json
        )

        XCTAssertEqual(result.unmeasuredModules, ["Library"])
        XCTAssertFalse(result.metrics.isEmpty, "the module is still scored, so its N/A rows are visible")
        XCTAssertTrue(result.metrics.contains { $0.coveragePercent == nil })
        XCTAssertTrue(
            CliApplication.unmeasuredWarning(result.unmeasuredModules)
                .contains("no coverage for module(s) Library")
        )
    }

    /// A report that measured nothing at all is the unambiguous failure, and it is what a broken
    /// export looks like: every method unscored, and the threshold compares against nothing.
    func testFailsWhenTheReportMeasuredNothing() throws {
        let root = try TempDir.make()
        let source = root.appendingPathComponent("Sources/Library/SearchModel.swift")
        try TempDir.write([
            "struct SearchModel {",
            "    func alpha() -> Int {",
            "        return 1",
            "    }",
            "}"
        ].joined(separator: "\n"), to: source)
        let json = root.appendingPathComponent("coverage.json")
        try TempDir.write(exportJSON(path: "/nowhere/Other.swift", functions: []), to: json)

        XCTAssertThrowsError(try CrapAnalyzer.analyze(projectRoot: root, files: [source], coverageJSON: json)) { error in
            XCTAssertEqual(
                CliApplication.message(for: error),
                "The coverage report measured nothing — no method could be scored. "
                    + "Check that the package's tests ran and that its coverage export succeeded."
            )
        }
    }

    /// One measured file is enough: a file may legitimately hold no instrumented code, because
    /// every declaration in it can sit behind a platform conditional the host build excludes.
    func testScoresWhenOneFileOfAModuleIsMeasured() throws {
        let root = try TempDir.make()
        let measured = root.appendingPathComponent("Sources/App/Measured.swift")
        let excluded = root.appendingPathComponent("Sources/App/UIKitOnly.swift")
        let body = [
            "struct Sample {",
            "    func alpha() -> Int {",
            "        return 1",
            "    }",
            "}"
        ].joined(separator: "\n")
        try TempDir.write(body, to: measured)
        try TempDir.write(body, to: excluded)

        let json = root.appendingPathComponent("coverage.json")
        try TempDir.write(exportJSON(path: measured.path, functions: [
            (name: "$s5alpha", startLine: 2, regions: [[2, 1, 3, 1, 1, 0, 0, 0]])
        ]), to: json)

        let result = try CrapAnalyzer.analyze(
            projectRoot: root,
            files: [measured, excluded],
            coverageJSON: json
        )

        XCTAssertEqual(result.metrics.count, 2)
        XCTAssertEqual(result.metrics.filter { $0.coveragePercent != nil }.count, 1)
        XCTAssertEqual(result.unmeasuredModules, [], "one measured file makes the module measured")
    }
}
