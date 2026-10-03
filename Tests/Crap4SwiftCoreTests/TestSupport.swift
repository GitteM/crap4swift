import Foundation
import XCTest
@testable import Crap4SwiftCore

enum TempDir {
    static func make(_ name: String = UUID().uuidString) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("crap4swift-tests-\(name)")
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    static func run(_ command: String, in directory: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = directory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}

final class RecordingExecutor: CommandExecutor {
    var commands: [[String]] = []
    var directories: [URL] = []
    var exitCode: Int32
    var onRun: ((URL) -> Void)?

    init(exitCode: Int32 = 0) {
        self.exitCode = exitCode
    }

    func run(_ command: [String], directory: URL) throws -> Int32 {
        commands.append(command)
        directories.append(directory)
        onRun?(directory)
        return exitCode
    }
}
