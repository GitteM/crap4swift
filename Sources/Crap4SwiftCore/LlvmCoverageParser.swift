import Foundation

enum LlvmCoverageParserError: Error {
    case unreadable(URL)
    case malformed(URL)

    var message: String {
        switch self {
        case .unreadable(let url):
            return "Unable to read LLVM coverage JSON: \(url.path)"
        case .malformed(let url):
            return "Unable to parse LLVM coverage JSON: \(url.path)"
        }
    }
}

/// Parses the JSON produced by SwiftPM (`swift test --enable-code-coverage`)
/// and/or `llvm-cov export`.
///
/// Coverage is keyed by `<absolute source path>#<function start line>`. Each
/// function's coverage fraction is derived from its code regions, mirroring
/// `crap4java`'s instruction-counter coverage.
enum LlvmCoverageParser {

    static func parse(_ url: URL?) throws -> [String: CoverageData] {
        guard let url else {
            return [:]
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        guard let data = try? Data(contentsOf: url) else {
            throw LlvmCoverageParserError.unreadable(url)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let document = root as? [String: Any] else {
            throw LlvmCoverageParserError.malformed(url)
        }

        var coverage: [String: CoverageData] = [:]
        let dataSections = document["data"] as? [[String: Any]] ?? []
        for section in dataSections {
            let functions = section["functions"] as? [[String: Any]] ?? []
            for function in functions {
                guard let regions = function["regions"] as? [[Any]],
                      let filenames = function["filenames"] as? [String],
                      let filename = filenames.first else {
                    continue
                }
                readFunction(regions, into: &coverage, filename: filename)
            }
        }
        return coverage
    }

    private static func readFunction(_ regions: [[Any]],
                                     into coverage: inout [String: CoverageData],
                                     filename: String) {
        var covered = 0
        var total = 0
        var startLine: Int?
        for region in regions {
            guard region.count >= 8 else {
                continue
            }
            let kind = integer(region[7])
            if kind != 0 {
                continue
            }
            let line = integer(region[0])
            let execution = integer(region[4])
            if startLine == nil {
                startLine = line
            }
            total += 1
            if execution > 0 {
                covered += 1
            }
        }
        guard let line = startLine else {
            return
        }
        let key = "\(canonicalPath(filename))#\(line)"
        coverage[key] = CoverageData(missedRegions: total - covered, coveredRegions: covered)
    }

    static func canonicalPath(_ filename: String) -> String {
        URL(fileURLWithPath: filename).standardizedFileURL.path
    }

    private static func integer(_ value: Any) -> Int {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let double = value as? Double {
            return Int(double)
        }
        if let string = value as? String, let int = Int(string) {
            return int
        }
        return 0
    }
}
