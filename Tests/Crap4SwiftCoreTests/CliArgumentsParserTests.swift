import XCTest
@testable import Crap4SwiftCore

final class CliArgumentsParserTests: XCTestCase {

    func testNoArgsMeansAllSources() throws {
        let args = try CliArgumentsParser.parse([])
        XCTAssertEqual(args.mode, .allSources)
    }

    func testChangedFlagMeansChangedSources() throws {
        let args = try CliArgumentsParser.parse(["--changed"])
        XCTAssertEqual(args.mode, .changedSources)
    }

    func testFileNamesMeanExplicitFiles() throws {
        let args = try CliArgumentsParser.parse(["Sources/App/A.swift", "Sources/App/B.swift"])
        XCTAssertEqual(args.mode, .explicitFiles)
        XCTAssertEqual(args.fileArgs, ["Sources/App/A.swift", "Sources/App/B.swift"])
    }

    func testUnknownFlagsAreIgnoredWhenCollectingExplicitFiles() throws {
        let args = try CliArgumentsParser.parse(["Sources/App/A.swift", "--bogus", "Sources/App/B.swift"])
        XCTAssertEqual(args.mode, .explicitFiles)
        XCTAssertEqual(args.fileArgs, ["Sources/App/A.swift", "Sources/App/B.swift"])
    }

    func testHelpMode() throws {
        let args = try CliArgumentsParser.parse(["--help"])
        XCTAssertEqual(args.mode, .help)
    }

    func testChangedCannotBeCombinedWithFiles() {
        XCTAssertThrowsError(try CliArgumentsParser.parse(["--changed", "Sources/App/A.swift"])) { error in
            XCTAssertEqual(error as? CliParseError, .changedCannotBeCombinedWithFileArguments)
        }
    }

    func testPlainFileDoesNotTriggerChangedMode() throws {
        let args = try CliArgumentsParser.parse(["Sources/App/A.swift"])
        XCTAssertEqual(args.mode, .explicitFiles)
        XCTAssertEqual(args.fileArgs, ["Sources/App/A.swift"])
    }
}
