import XCTest
@testable import Crap4SwiftCore

final class MainTests: XCTestCase {

    func testHelpWritesUsageToStdout() throws {
        let root = try TempDir.make()
        var out = ""
        var err = ""

        let exit = try Main.run(["--help"], projectRoot: root, out: { out += $0 }, err: { err += $0 })

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(out.contains("Usage:"))
        XCTAssertTrue(err.isEmpty)
    }

    func testExplicitFileArgsAreAnalyzed() throws {
        let root = try TempDir.make()
        try TempDir.write([
            "struct Sample {",
            "    func alpha(_ a: Bool) -> Int {",
            "        if a {",
            "            return 1",
            "        }",
            "        return 0",
            "    }",
            "}"
        ].joined(separator: "\n"), to: root.appendingPathComponent("Sources/App/Sample.swift"))

        var out = ""
        let exit = try Main.run(
            ["Sources/App/Sample.swift"],
            projectRoot: root,
            out: { out += $0 },
            err: { _ in },
            coverageRunner: CoverageRunner(executor: RecordingExecutor())
        )

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(out.contains("Sample"))
        XCTAssertTrue(out.contains("alpha"))
    }

    func testMaxCrapReturnsLargestNonNullScore() {
        let metrics = [
            MethodMetrics(methodName: "alpha", className: "Sample", complexity: 1, coveragePercent: nil, crapScore: nil),
            MethodMetrics(methodName: "beta", className: "Sample", complexity: 1, coveragePercent: 75.0, crapScore: 4.5),
            MethodMetrics(methodName: "gamma", className: "Sample", complexity: 1, coveragePercent: 85.0, crapScore: 7.0)
        ]

        XCTAssertEqual(Main.maxCrap(metrics), 7.0)
    }

    func testPublicEntryPointRejectsChangedCombinedWithFile() throws {
        let root = try TempDir.make()
        var out = ""
        var err = ""

        let exit = Crap4Swift.run(["--changed", "Sources/App/A.swift"], projectRoot: root, out: { out += $0 }, err: { err += $0 })

        XCTAssertEqual(exit, 1)
        XCTAssertTrue(out.contains("Usage:"))
        XCTAssertTrue(err.contains("--changed cannot be combined"))
    }
}
