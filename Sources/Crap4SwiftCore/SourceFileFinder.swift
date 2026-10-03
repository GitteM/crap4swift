import Foundation

enum SourceFileFinder {

    static func findAllSwiftFilesUnderSources(_ projectRoot: URL) -> [URL] {
        let sources = projectRoot.appendingPathComponent("Sources")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sources.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return []
        }

        guard let enumerator = FileManager.default.enumerator(
            at: sources,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url.standardizedFileURL)
        }
        files.sort { $0.path < $1.path }
        return files
    }
}
