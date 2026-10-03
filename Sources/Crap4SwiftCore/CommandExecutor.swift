import Foundation

public protocol CommandExecutor {
    func run(_ command: [String], directory: URL) throws -> Int32
}
