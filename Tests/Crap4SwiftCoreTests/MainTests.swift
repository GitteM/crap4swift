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
        XCTAssertTrue(out.contains("--version"))
        XCTAssertTrue(err.isEmpty)
    }

    func testVersionWritesTheVersionToStdout() throws {
        let root = try TempDir.make()
        var out = ""
        var err = ""

        let exit = try Main.run(["--version"], projectRoot: root, out: { out += $0 }, err: { err += $0 })

        XCTAssertEqual(exit, 0)
        XCTAssertEqual(out, "crap4swift \(Main.version)\n")
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

        let executor = RecordingExecutor()
        executor.onRun = { moduleRoot in
            let source = moduleRoot.appendingPathComponent("Sources/App/Sample.swift")
            let json = moduleRoot.appendingPathComponent(".build/out/Products/Debug/codecov/App.json")
            let body = #"{"data":[{"files":[],"functions":[{"name":"$s5alpha","count":1,"filenames":["\#(source.path)"],"regions":[[2,1,7,1,1,0,0,0]]}]}],"type":"llvm.coverage.json.export","version":"3.0.1"}"#
            try? TempDir.write(body, to: json)
        }

        var out = ""
        let exit = try Main.run(
            ["Sources/App/Sample.swift"],
            projectRoot: root,
            out: { out += $0 },
            err: { _ in },
            coverageRunner: CoverageRunner(executor: executor)
        )

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(out.contains("Sample"))
        XCTAssertTrue(out.contains("alpha"))
    }

    /// A module no test binary links is **warned about**, not failed: `Mocks` (`#if DEBUG`) and
    /// `ServiceProtocols` are both legitimately absent from their package's export, so failing here
    /// would refuse two of the three real packages. The failure is reserved for a report that
    /// measured nothing at all.
    func testUnmeasuredModuleIsWarnedAboutRatherThanFailing() throws {
        let root = try TempDir.make()
        let sample = root.appendingPathComponent("Sources/App/Sample.swift")
        try TempDir.write([
            "struct Sample {",
            "    func alpha() -> Int {",
            "        return 1",
            "    }",
            "}"
        ].joined(separator: "\n"), to: sample)
        // A second module the report carries, so the run is otherwise healthy.
        let other = root.appendingPathComponent("Sources/Core/Pitch.swift")
        try TempDir.write([
            "struct Pitch {",
            "    func beta() -> Int {",
            "        return 2",
            "    }",
            "}"
        ].joined(separator: "\n"), to: other)

        let executor = RecordingExecutor()
        executor.onRun = { moduleRoot in
            let json = moduleRoot.appendingPathComponent(".build/out/Products/Debug/codecov/App.json")
            let body = #"{"data":[{"files":[],"functions":[{"name":"$s4beta","count":1,"filenames":["\#(other.path)"],"regions":[[2,1,3,1,1,0,0,0]]}]}],"type":"llvm.coverage.json.export","version":"3.0.1"}"#
            try? TempDir.write(body, to: json)
        }

        var err = ""
        let exit = try Main.run(
            ["Sources/App/Sample.swift", "Sources/Core/Pitch.swift"],
            projectRoot: root,
            out: { _ in },
            err: { err += $0 },
            coverageRunner: CoverageRunner(executor: executor)
        )

        XCTAssertEqual(exit, 0, "an unlinked module must not block the gate")
        XCTAssertTrue(err.contains("no coverage for module(s) App"))
    }

    /// The one unambiguous failure: the report measured nothing, so no score exists to compare.
    func testAReportThatMeasuredNothingFails() throws {
        let root = try TempDir.make()
        try TempDir.write([
            "struct Sample {",
            "    func alpha() -> Int {",
            "        return 1",
            "    }",
            "}"
        ].joined(separator: "\n"), to: root.appendingPathComponent("Sources/App/Sample.swift"))

        XCTAssertThrowsError(try Main.run(
            ["Sources/App/Sample.swift"],
            projectRoot: root,
            out: { _ in },
            err: { _ in },
            coverageRunner: CoverageRunner(executor: RecordingExecutor())
        )) { error in
            XCTAssertEqual(
                CliApplication.message(for: error),
                "The coverage report measured nothing — no method could be scored. "
                    + "Check that the package's tests ran and that its coverage export succeeded."
            )
        }
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
