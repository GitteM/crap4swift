import Foundation

enum CrapAnalyzer {

    static func analyze(projectRoot: URL, files: [URL], coverageJSON: URL?) throws -> [MethodMetrics] {
        let coverage = try LlvmCoverageParser.parse(coverageJSON)
        var metrics: [MethodMetrics] = []

        for file in files {
            guard FileManager.default.fileExists(atPath: file.path) else {
                continue
            }
            guard let source = try? String(contentsOf: file, encoding: .utf8) else {
                throw CrapAnalyzerError.unreadableSource(file)
            }

            let fallbackName = classNameFromSource(file: file, source: source)
            let path = file.standardizedFileURL.path
            for method in SwiftMethodParser.parse(source) {
                let coveragePercent = lookupCoverage(
                    coverage,
                    path: path,
                    startLine: method.startLine,
                    endLine: method.endLine
                )
                let crap = CrapScore.calculate(complexity: method.complexity, coveragePercent: coveragePercent)
                metrics.append(MethodMetrics(
                    methodName: method.name,
                    className: method.enclosingType ?? fallbackName,
                    complexity: method.complexity,
                    coveragePercent: coveragePercent,
                    crapScore: crap
                ))
            }
        }

        return sortByCrap(metrics)
    }

    static func classNameFromSource(file: URL, source: String) -> String {
        file.deletingPathExtension().lastPathComponent
    }

    /// Coverage is preferred from an exact `<path>#<startLine>` match; when that
    /// is absent the nearest coverage entry whose start line falls inside the
    /// method's line span is used, mirroring `crap4java`'s nearest-match rule.
    static func lookupCoverage(_ coverage: [String: CoverageData],
                               path: String,
                               startLine: Int,
                               endLine: Int) -> Double? {
        if let exact = coverage["\(path)#\(startLine)"] {
            return exact.coveragePercent
        }

        let prefix = "\(path)#"
        var nearest: CoverageData?
        var bestDistance = Int.max
        var bestLine = Int.max
        for (key, data) in coverage where key.hasPrefix(prefix) {
            let line = parseTrailingLine(key, prefixLength: prefix.count)
            guard line >= startLine, line <= endLine else {
                continue
            }
            let distance = abs(line - startLine)
            if distance < bestDistance || (distance == bestDistance && line < bestLine) {
                bestDistance = distance
                bestLine = line
                nearest = data
            }
        }
        return nearest?.coveragePercent
    }

    static func parseTrailingLine(_ key: String, prefixLength: Int = 0) -> Int {
        guard key.count > prefixLength else {
            return Int.max
        }
        let suffix = key.dropFirst(prefixLength)
        guard let value = Int(suffix) else {
            return Int.max
        }
        return value
    }

    static func sortByCrap(_ metrics: [MethodMetrics]) -> [MethodMetrics] {
        metrics.enumerated()
            .sorted { lhs, rhs in
                switch (lhs.element.crapScore, rhs.element.crapScore) {
                case (nil, nil):
                    return lhs.offset < rhs.offset
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                case let (left?, right?):
                    if left == right {
                        return lhs.offset < rhs.offset
                    }
                    return left > right
                }
            }
            .map { $0.element }
    }
}

enum CrapAnalyzerError: Error {
    case unreadableSource(URL)

    var message: String {
        switch self {
        case .unreadableSource(let url):
            return "Unable to read source file: \(url.path)"
        }
    }
}
