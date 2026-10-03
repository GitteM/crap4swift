import XCTest
@testable import Crap4SwiftCore

final class ChangedFileDetectorTests: XCTestCase {

    func testFindsModifiedAndUntrackedSwiftFiles() throws {
        let root = try TempDir.make()
        TempDir.run("git init -q", in: root)
        TempDir.run("git config user.email test@example.com && git config user.name test", in: root)

        let sources = root.appendingPathComponent("Sources/App")
        let tracked = sources.appendingPathComponent("Tracked.swift")
        try TempDir.write("struct Tracked {}\n", to: tracked)

        TempDir.run("git add . && git commit -qm init", in: root)

        try TempDir.write("struct Tracked { let x = 1 }\n", to: tracked)
        let untracked = sources.appendingPathComponent("NewFile.swift")
        try TempDir.write("struct NewFile {}\n", to: untracked)
        try TempDir.write("ignore me\n", to: root.appendingPathComponent("README.md"))

        let changed = try ChangedFileDetector.changedSwiftFiles(projectRoot: root)

        XCTAssertEqual(changed.map(\.path), [
            untracked.standardizedFileURL.path,
            tracked.standardizedFileURL.path
        ].sorted())
    }

    func testIncludesGitErrorOutputWhenStatusFails() throws {
        let root = try TempDir.make()
        XCTAssertThrowsError(try ChangedFileDetector.changedSwiftFiles(projectRoot: root)) { error in
            XCTAssertTrue(CliApplication.message(for: error).contains("not a git repository"))
        }
    }

    func testFiltersChangedFilesToSourcesTreeOnly() throws {
        let root = try TempDir.make()
        TempDir.run("git init -q", in: root)
        TempDir.run("git config user.email test@example.com && git config user.name test", in: root)

        let sources = root.appendingPathComponent("Sources/App")
        let tracked = sources.appendingPathComponent("Tracked.swift")
        try TempDir.write("struct Tracked {}\n", to: tracked)
        TempDir.run("git add . && git commit -qm init", in: root)

        try TempDir.write("struct Tracked { let x = 1 }\n", to: tracked)
        try TempDir.write("struct T {}\n", to: root.appendingPathComponent("Tests/App/Tests.swift"))

        let changed = try ChangedFileDetector.changedSwiftFilesUnderSources(projectRoot: root)

        XCTAssertEqual(changed.map(\.path), [tracked.standardizedFileURL.path])
    }

    func testCandidateLineRequiresAtLeastFourCharacters() {
        XCTAssertFalse(ChangedFileDetector.isCandidateLine(nil))
        XCTAssertFalse(ChangedFileDetector.isCandidateLine(""))
        XCTAssertFalse(ChangedFileDetector.isCandidateLine("abc"))
        XCTAssertTrue(ChangedFileDetector.isCandidateLine("abcd"))
    }

    func testRenameTargetUsesReplacementSide() {
        XCTAssertEqual(ChangedFileDetector.renameTarget("Sources/Old.swift -> Sources/New.swift"), "Sources/New.swift")
        XCTAssertEqual(ChangedFileDetector.renameTarget(" -> New.swift"), "New.swift")
        XCTAssertEqual(ChangedFileDetector.renameTarget("Plain.swift"), "Plain.swift")
    }
}
