import XCTest
@testable import Crap4SwiftCore

final class CoverageRunnerTests: XCTestCase {

    /// A `.build` shaped like a real SwiftPM run: one coverage directory holding the merged
    /// profile, and the test bundles' executables beside it.
    @discardableResult
    private func writeProducts(_ root: URL,
                               bundles: [String] = ["ATests", "BTests"]) throws -> URL {
        let products = root.appendingPathComponent(".build/out/Products/Debug")
        let codecov = products.appendingPathComponent("codecov")
        try TempDir.write("profile", to: codecov.appendingPathComponent("default.profdata"))
        for bundle in bundles {
            try TempDir.write(
                "binary",
                to: products.appendingPathComponent("\(bundle).xctest/Contents/MacOS/\(bundle)")
            )
        }
        return codecov
    }

    func testDeletesStaleCoverageAndRunsSwiftCoverageCommand() throws {
        let root = try TempDir.make()
        let codecov = root.appendingPathComponent(".build/out/Products/Debug/codecov")
        try TempDir.write("stale", to: codecov.appendingPathComponent("old.json"))
        try TempDir.write("stale", to: codecov.appendingPathComponent("default.profdata"))

        let executor = RecordingExecutor(exitCode: 0)
        let runner = CoverageRunner(executor: executor)

        try runner.generateCoverage(moduleRoot: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: codecov.path))
        XCTAssertEqual(executor.commands.first, ["swift", "test", "--enable-code-coverage"])
        XCTAssertEqual(executor.directories.first?.standardizedFileURL.path, root.standardizedFileURL.path)
        // Nothing was left to export from, so no export ran.
        XCTAssertTrue(executor.outputCommands.isEmpty)
    }

    func testFailsWhenCoverageCommandFails() throws {
        let root = try TempDir.make()
        let runner = CoverageRunner(executor: RecordingExecutor(exitCode: 2))

        XCTAssertThrowsError(try runner.generateCoverage(moduleRoot: root)) { error in
            XCTAssertEqual(error as? CoverageRunnerError, .commandFailed(2))
            XCTAssertEqual(CliApplication.message(for: error), "Coverage command failed with exit 2")
        }
    }

    func testExportsCompleteCoverageAcrossEveryTestBundle() throws {
        let root = try TempDir.make()
        let executor = RecordingExecutor(exitCode: 0)
        executor.onRun = { [self] _ in
            try? writeProducts(root)
        }
        executor.onRunWritingOutput = { output in
            try? TempDir.write("{}", to: output)
        }

        try CoverageRunner(executor: executor).generateCoverage(moduleRoot: root)

        let command = try XCTUnwrap(executor.outputCommands.first)
        XCTAssertEqual(executor.outputCommands.count, 1)
        XCTAssertEqual(Array(command.prefix(4)), ["xcrun", "llvm-cov", "export", "-instr-profile"])
        XCTAssertEqual(URL(fileURLWithPath: command[4]).lastPathComponent, "default.profdata")
        // First binary positional, every other one after `-object`.
        XCTAssertEqual(
            command.dropFirst(5).map { URL(fileURLWithPath: $0).lastPathComponent },
            ["ATests", "-object", "BTests"]
        )
        XCTAssertEqual(
            executor.outputURLs.first?.lastPathComponent,
            CoverageRunner.exportFileName
        )
    }

    func testFailsWhenTheExportFails() throws {
        let root = try TempDir.make()
        let executor = RecordingExecutor(exitCode: 0)
        executor.outputExitCode = 3
        executor.onRun = { [self] _ in
            try? writeProducts(root)
        }

        XCTAssertThrowsError(try CoverageRunner(executor: executor).generateCoverage(moduleRoot: root)) { error in
            XCTAssertEqual(error as? CoverageRunnerError, .exportFailed(3))
        }
    }

    func testExportPlanPrefersTheCodecovDirectoryHoldingAProfile() throws {
        let root = try TempDir.make()
        // An empty coverage directory sorts first; it must not be chosen.
        try TempDir.write("{}", to: root.appendingPathComponent(".build/arm64/debug/codecov/Empty.json"))
        let codecov = try writeProducts(root)

        let plan = try XCTUnwrap(CoverageRunner.exportPlan(in: root))

        XCTAssertEqual(plan.codecovDirectory.path, codecov.standardizedFileURL.path)
        XCTAssertEqual(plan.binaries.map(\.lastPathComponent), ["ATests", "BTests"])
    }

    func testExportPlanIsNilWithoutATestBundle() throws {
        let root = try TempDir.make()
        let codecov = root.appendingPathComponent(".build/out/Products/Debug/codecov")
        try TempDir.write("profile", to: codecov.appendingPathComponent("default.profdata"))

        XCTAssertNil(CoverageRunner.exportPlan(in: root))
    }

    func testFindsCodecovJSONAfterGeneration() throws {
        let root = try TempDir.make()
        let codecov = root.appendingPathComponent(".build/out/Products/Debug/codecov")
        let json = codecov.appendingPathComponent("App.json")
        try TempDir.write("{}", to: json)

        XCTAssertEqual(CoverageRunner.codecovJSON(in: root)?.standardizedFileURL.path, json.standardizedFileURL.path)
    }

    func testPrefersTheToolsOwnExportOverSwiftPMsPartialReport() throws {
        let root = try TempDir.make()
        let codecov = root.appendingPathComponent(".build/out/Products/Debug/codecov")
        try TempDir.write("{}", to: codecov.appendingPathComponent("App.json"))
        let own = codecov.appendingPathComponent(CoverageRunner.exportFileName)
        try TempDir.write("{}", to: own)

        XCTAssertEqual(CoverageRunner.codecovJSON(in: root)?.standardizedFileURL.path, own.standardizedFileURL.path)
    }

    func testReturnsNilWhenNoCodecovJSON() throws {
        let root = try TempDir.make()
        XCTAssertNil(CoverageRunner.codecovJSON(in: root))
    }
}

final class ProcessCommandExecutorTests: XCTestCase {

    func testReturnsExitCodeFromLaunchedProcess() throws {
        let root = try TempDir.make()
        let exit = try ProcessCommandExecutor().run(["/bin/sh", "-c", "exit 7"], directory: root)
        XCTAssertEqual(exit, 7)
    }

    func testWritesStandardOutputToTheGivenFile() throws {
        let root = try TempDir.make()
        let output = root.appendingPathComponent("export.json")

        let exit = try ProcessCommandExecutor().run(
            ["/bin/sh", "-c", "printf 'exported'"],
            directory: root,
            writingStandardOutputTo: output
        )

        XCTAssertEqual(exit, 0)
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "exported")
    }
}
