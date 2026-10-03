import Foundation

enum ChangedFileDetectorError: Error {
    case gitStatusFailed(String)

    var message: String {
        switch self {
        case .gitStatusFailed(let output):
            return "git status failed: \(output)"
        }
    }
}

enum ChangedFileDetector {

    static func changedSwiftFiles(projectRoot: URL) throws -> [URL] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", projectRoot.path, "status", "--porcelain"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw ChangedFileDetectorError.gitStatusFailed(output)
        }

        var files: [URL] = []
        for line in output.split(whereSeparator: { $0.isNewline }) {
            if let file = parseStatusLine(projectRoot: projectRoot, line: String(line)) {
                files.append(file)
            }
        }
        files.sort { $0.path < $1.path }
        return files
    }

    static func changedSwiftFilesUnderSources(projectRoot: URL) throws -> [URL] {
        let sourcesPrefix = projectRoot.appendingPathComponent("Sources").standardizedFileURL.path
        return try changedSwiftFiles(projectRoot: projectRoot).filter {
            $0.standardizedFileURL.path.hasPrefix(sourcesPrefix)
        }
    }

    static func parseStatusLine(projectRoot: URL, line: String) -> URL? {
        guard isCandidateLine(line) else {
            return nil
        }
        let pathPart = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        let finalPath = renameTarget(pathPart)
        guard finalPath.hasSuffix(".swift") else {
            return nil
        }
        return projectRoot.appendingPathComponent(finalPath).standardizedFileURL
    }

    static func isCandidateLine(_ line: String?) -> Bool {
        guard let line else {
            return false
        }
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            return false
        }
        return line.count >= 4
    }

    static func renameTarget(_ pathPart: String) -> String {
        guard let range = pathPart.range(of: " -> ") else {
            return pathPart
        }
        return String(pathPart[range.upperBound...])
    }
}
