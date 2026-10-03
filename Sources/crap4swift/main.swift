import Foundation
import Crap4SwiftCore

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
let exitCode = Crap4Swift.run(
    Array(CommandLine.arguments.dropFirst()),
    projectRoot: projectRoot,
    out: { print($0, terminator: "") },
    err: { FileHandle.standardError.write(Data($0.utf8)) }
)
exit(exitCode)
