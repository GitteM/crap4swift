import XCTest
@testable import Crap4SwiftCore

final class CoverageRunnerTests: XCTestCase {

    func testDeletesStaleCoverageAndRunsSwiftCoverageCommand() throws {
        let root = try TempDir.make()
        let codecov = root.appendingPathComponent(".build/out/Products/Debug/codecov")
        try TempDir.write("stale", to: codecov.appendingPathComponent("old.json"))
        try TempDir.write("stale", to: codecov.appendingPathComponent("default.profdata"))

        let executor = RecordingExecutor(exitCode: 0)
        let runner = CoverageRunner(executor: executor)

        try runner.generateCoverage(moduleRoot: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: codecov.path))
        XCTAssertEqual(
            executor.commands.first,
            ["swift", "test", "--enable-code-coverage", "--build-system", "native"]
        )
        XCTAssertEqual(executor.directories.first?.standardizedFileURL.path, root.standardizedFileURL.path)
    }

    func testFailsWhenCoverageCommandFails() throws {
        let root = try TempDir.make()
        let runner = CoverageRunner(executor: RecordingExecutor(exitCode: 2))

        XCTAssertThrowsError(try runner.generateCoverage(moduleRoot: root)) { error in
            XCTAssertEqual(error as? CoverageRunnerError, .commandFailed(2))
            XCTAssertEqual(CliApplication.message(for: error), "Coverage command failed with exit 2")
        }
    }

    func testFindsCodecovJSONAfterGeneration() throws {
        let root = try TempDir.make()
        let codecov = root.appendingPathComponent(".build/out/Products/Debug/codecov")
        let json = codecov.appendingPathComponent("App.json")
        try TempDir.write("{}", to: json)

        XCTAssertEqual(CoverageRunner.codecovJSON(in: root)?.standardizedFileURL.path, json.standardizedFileURL.path)
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
}
