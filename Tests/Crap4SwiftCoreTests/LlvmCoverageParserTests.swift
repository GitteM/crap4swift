import XCTest
@testable import Crap4SwiftCore

final class LlvmCoverageParserTests: XCTestCase {

    private func exportJSON(functions: String) -> String {
        """
        {"data":[{"files":[],"functions":[\(functions)]}],"type":"llvm.coverage.json.export","version":"3.0.1"}
        """
    }

    func testParsesRegionCoverageByFunctionStartLine() throws {
        let root = try TempDir.make()
        let json = root.appendingPathComponent("coverage.json")
        let source = root.appendingPathComponent("Sources/App/Sample.swift").path
        try TempDir.write(exportJSON(functions: """
        {"name":"$s5alpha","count":2,"filenames":["\(source)"],"regions":[[4,42,9,6,2,0,0,0],[5,12,5,16,2,0,0,0],[5,17,7,10,1,0,0,0],[7,10,8,17,1,0,0,0]]}
        """), to: json)

        let coverage = try LlvmCoverageParser.parse(json)

        // 4 code regions, all executed -> 100%
        XCTAssertEqual(coverage["\(LlvmCoverageParser.canonicalPath(source))#4"]?.coveragePercent ?? -1, 100.0, accuracy: 0.001)
    }

    func testComputesPartialCoverage() throws {
        let root = try TempDir.make()
        let json = root.appendingPathComponent("coverage.json")
        let source = root.appendingPathComponent("Sources/App/Sample.swift").path
        try TempDir.write(exportJSON(functions: """
        {"name":"$s4beta","count":1,"filenames":["\(source)"],"regions":[[11,41,17,6,1,0,0,0],[12,16,12,21,1,0,0,0],[13,9,13,25,1,0,0,0],[14,9,14,25,0,0,0,0],[15,9,15,26,0,0,0,0]]}
        """), to: json)

        let coverage = try LlvmCoverageParser.parse(json)

        // 5 code regions, 3 executed -> 60%
        XCTAssertEqual(coverage["\(LlvmCoverageParser.canonicalPath(source))#11"]?.coveragePercent ?? -1, 60.0, accuracy: 0.001)
    }

    func testIgnoresSkippedRegions() throws {
        let root = try TempDir.make()
        let json = root.appendingPathComponent("coverage.json")
        let source = root.appendingPathComponent("Sources/App/Sample.swift").path
        // region kind != 0 (index 7) is a skipped region and must not count
        try TempDir.write(exportJSON(functions: """
        {"name":"$s4main","count":1,"filenames":["\(source)"],"regions":[[3,1,10,1,1,0,0,0],[4,1,4,10,0,0,0,2]]}
        """), to: json)

        let coverage = try LlvmCoverageParser.parse(json)

        XCTAssertEqual(coverage["\(LlvmCoverageParser.canonicalPath(source))#3"]?.coveragePercent ?? -1, 100.0, accuracy: 0.001)
    }

    func testReturnsEmptyForMissingFile() throws {
        let root = try TempDir.make()
        let missing = root.appendingPathComponent("absent.json")
        XCTAssertTrue(try LlvmCoverageParser.parse(missing).isEmpty)
        XCTAssertTrue(try LlvmCoverageParser.parse(nil).isEmpty)
    }

    func testThrowsOnMalformedJSON() throws {
        let root = try TempDir.make()
        let json = root.appendingPathComponent("coverage.json")
        try TempDir.write("{ not valid json", to: json)

        XCTAssertThrowsError(try LlvmCoverageParser.parse(json))
    }
}
