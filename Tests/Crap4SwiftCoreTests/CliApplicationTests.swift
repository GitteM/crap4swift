import XCTest
@testable import Crap4SwiftCore

final class CliApplicationTests: XCTestCase {

    private func emptyCoverageJSON() -> String {
        """
        {"data":[{"files":[],"functions":[]}],"type":"llvm.coverage.json.export","version":"3.0.1"}
        """
    }

    private func writeCoverage(into moduleRoot: URL) {
        let json = moduleRoot.appendingPathComponent(".build/out/Products/Debug/codecov/App.json")
        try? TempDir.write(emptyCoverageJSON(), to: json)
    }

    private func makeApplication(_ root: URL,
                                 executor: RecordingExecutor,
                                 out: @escaping (String) -> Void,
                                 err: @escaping (String) -> Void) -> CliApplication {
        CliApplication(projectRoot: root, out: out, err: err, coverageRunner: CoverageRunner(executor: executor))
    }

    func testParseErrorsReturnUsageAndExitOne() throws {
        let root = try TempDir.make()
        var out = ""
        var err = ""
        let app = makeApplication(root, executor: RecordingExecutor(), out: { out += $0 }, err: { err += $0 })

        let exit = try app.execute(["--changed", "Sources/App/A.swift"])

        XCTAssertEqual(exit, 1)
        XCTAssertTrue(out.contains("Usage:"))
        XCTAssertTrue(err.contains("--changed cannot be combined with file arguments"))
    }

    func testReturnsZeroWhenNoFilesAreFound() throws {
        let root = try TempDir.make()
        var out = ""
        let app = makeApplication(root, executor: RecordingExecutor(), out: { out += $0 }, err: { _ in })

        let exit = try app.execute([])

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(out.contains("No Swift files to analyze."))
    }

    func testDoesNotWarnWhenCoverageJSONExists() throws {
        let root = try TempDir.make()
        try TempDir.write([
            "struct Sample {",
            "    func alpha() -> Int {",
            "        return 1",
            "    }",
            "}"
        ].joined(separator: "\n"), to: root.appendingPathComponent("Sources/App/Sample.swift"))

        let executor = RecordingExecutor(exitCode: 0)
        executor.onRun = { self.writeCoverage(into: $0) }
        var out = ""
        var err = ""

        let exit = try makeApplication(root, executor: executor, out: { out += $0 }, err: { err += $0 })
            .execute(["Sources/App/Sample.swift"])

        XCTAssertEqual(exit, 0)
        XCTAssertTrue(out.contains("Sample"))
        XCTAssertTrue(out.contains("alpha"))
        XCTAssertFalse(err.contains("Warning: Swift coverage JSON not found"))
    }

    func testExplicitFileUsesOwningModuleForCoverage() throws {
        let root = try TempDir.make()
        let moduleRoot = root.appendingPathComponent("Packages/App")
        try TempDir.write("<project/>", to: moduleRoot.appendingPathComponent("Package.swift"))
        try TempDir.write([
            "struct Sample {",
            "    func alpha() -> Int {",
            "        return 1",
            "    }",
            "}"
        ].joined(separator: "\n"), to: moduleRoot.appendingPathComponent("Sources/App/Sample.swift"))

        let executor = RecordingExecutor(exitCode: 0)
        executor.onRun = { self.writeCoverage(into: $0) }
        var out = ""

        let exit = try makeApplication(root, executor: executor, out: { out += $0 }, err: { _ in })
            .execute(["Packages/App/Sources/App/Sample.swift"])

        XCTAssertEqual(exit, 0)
        XCTAssertEqual(executor.directories.map { $0.standardizedFileURL.path }, [moduleRoot.standardizedFileURL.path])
        XCTAssertTrue(out.contains("Sample"))
    }

    func testThresholdExceededUsesStrictlyGreaterThanEight() {
        XCTAssertFalse(CliApplication.thresholdExceeded(8.0))
        XCTAssertTrue(CliApplication.thresholdExceeded(8.1))
    }

    func testModuleRootForFindsNearestAncestorWithPackageManifest() throws {
        let root = try TempDir.make()
        let moduleRoot = root.appendingPathComponent("Packages/App")
        let source = moduleRoot.appendingPathComponent("Sources/App/Sample.swift")
        try TempDir.write("<project/>", to: moduleRoot.appendingPathComponent("Package.swift"))
        try TempDir.write("struct Sample {}", to: source)

        XCTAssertEqual(
            CliApplication.moduleRootFor(workspaceRoot: root, file: source).standardizedFileURL.path,
            moduleRoot.standardizedFileURL.path
        )
    }
}
