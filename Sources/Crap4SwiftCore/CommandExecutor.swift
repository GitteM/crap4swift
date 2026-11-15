import Foundation

public protocol CommandExecutor {
    func run(_ command: [String], directory: URL) throws -> Int32

    /// Runs `command` with its standard output written to `output` rather than inherited.
    ///
    /// Needed for commands whose *result is a file* rather than a stream — `llvm-cov export`
    /// writes its JSON to standard output and has no output-file option — and for keeping that
    /// JSON out of the report the gate reads.
    func run(_ command: [String], directory: URL, writingStandardOutputTo output: URL) throws -> Int32
}

extension CommandExecutor {
    /// The implementation every conformer gets for free. It launches the process through
    /// `/usr/bin/env`, so a bare command name resolves on the caller's `PATH`, exactly as the
    /// inherited-output overload does.
    public func run(_ command: [String],
                    directory: URL,
                    writingStandardOutputTo output: URL) throws -> Int32 {
        if !FileManager.default.fileExists(atPath: output.path) {
            FileManager.default.createFile(atPath: output.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.currentDirectoryURL = directory
        process.standardOutput = handle
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
