import Foundation

enum CoverageRunnerError: Error, Equatable {
    case commandFailed(Int32)

    var message: String {
        switch self {
        case .commandFailed(let exit):
            return "Coverage command failed with exit \(exit)"
        }
    }
}

final class CoverageRunner {

    private let executor: CommandExecutor

    init(executor: CommandExecutor) {
        self.executor = executor
    }

    func generateCoverage(moduleRoot: URL) throws {
        try deleteStaleArtifacts(moduleRoot: moduleRoot)

        let exit = try executor.run(CoverageRunner.coverageCommand, directory: moduleRoot)
        if exit != 0 {
            throw CoverageRunnerError.commandFailed(exit)
        }
    }

    static let coverageCommand = ["swift", "test", "--enable-code-coverage"]

    private func deleteStaleArtifacts(moduleRoot: URL) throws {
        for directory in CoverageRunner.codecovDirectories(in: moduleRoot) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: - Artifact discovery

    static func codecovDirectories(in moduleRoot: URL) -> [URL] {
        let build = moduleRoot.appendingPathComponent(".build")
        guard let enumerator = FileManager.default.enumerator(
            at: build,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return []
        }

        var directories: [URL] = []
        for case let url as URL in enumerator where url.lastPathComponent == "codecov" {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                directories.append(url.standardizedFileURL)
            }
        }
        directories.sort { $0.path < $1.path }
        return directories
    }

    static func codecovJSON(in moduleRoot: URL) -> URL? {
        for directory in codecovDirectories(in: moduleRoot) {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }
            let jsonFiles = contents
                .filter { $0.pathExtension == "json" }
                .sorted { $0.path < $1.path }
            if let first = jsonFiles.first {
                return first
            }
        }
        return nil
    }
}
