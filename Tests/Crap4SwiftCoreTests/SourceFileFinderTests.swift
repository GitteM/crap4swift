import XCTest
@testable import Crap4SwiftCore

final class SourceFileFinderTests: XCTestCase {

    func testFindsAllSwiftFilesUnderSourcesOnly() throws {
        let root = try TempDir.make()
        let inSources = root.appendingPathComponent("Sources/App/Sample.swift")
        try TempDir.write("struct Sample {}\n", to: inSources)

        let outOfSources = root.appendingPathComponent("Other/Elsewhere.swift")
        try TempDir.write("struct Elsewhere {}\n", to: outOfSources)

        let files = SourceFileFinder.findAllSwiftFilesUnderSources(root)

        XCTAssertEqual(files.map { $0.standardizedFileURL.path }, [inSources.standardizedFileURL.path])
    }

    func testReturnsEmptyWhenNoSourcesDirectory() throws {
        let root = try TempDir.make()
        XCTAssertTrue(SourceFileFinder.findAllSwiftFilesUnderSources(root).isEmpty)
    }
}
