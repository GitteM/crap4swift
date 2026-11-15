import Foundation

enum CrapAnalyzer {

    /// The metrics, and what the report could not speak to.
    struct Result {
        let metrics: [MethodMetrics]
        /// Modules with scoreable code that the report carries **no record of at all** — their code
        /// is not linked into any test binary of this package, so nothing in them can be scored.
        let unmeasuredModules: [String]
    }

    static func analyze(projectRoot: URL, files: [URL], coverageJSON: URL?) throws -> Result {
        let coverage = try LlvmCoverageParser.parse(coverageJSON)
        let measuredFiles = LlvmCoverageParser.measuredPaths(in: coverage)
        var metrics: [MethodMetrics] = []
        var measurement = ModuleMeasurement()

        for file in files {
            guard FileManager.default.fileExists(atPath: file.path) else {
                continue
            }
            guard let source = try? String(contentsOf: file, encoding: .utf8) else {
                throw CrapAnalyzerError.unreadableSource(file)
            }

            let fallbackName = classNameFromSource(file: file, source: source)
            let path = file.standardizedFileURL.path
            let methods = SwiftMethodParser.parse(source)
            measurement.record(
                module: moduleName(ofPath: path),
                methodCount: methods.count,
                isMeasured: measuredFiles.contains(path)
            )
            for method in methods {
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

        // A module with scoreable code that contributed **nothing** to the report is not
        // "untested", and it is not necessarily a broken report either: measured 2026-11-15,
        // `Mocks` (`#if DEBUG`, used by other packages' tests) and `ServiceProtocols` (one extension
        // method its own package's tests never call) are both absent from their package's export
        // because no test binary links them. So it is reported, and only a report that measured
        // **nothing at all** fails the run — that one is unambiguous.
        let unmeasured = measurement.unmeasuredModules
        if !metrics.isEmpty && !measurement.hasMeasuredAnyModule {
            throw CrapAnalyzerError.nothingMeasured
        }

        return Result(metrics: sortByCrap(metrics), unmeasuredModules: unmeasured)
    }

    /// The SwiftPM target a source file belongs to: the path component after `Sources`.
    /// `nil` for a file outside a `Sources` tree, which is never a module of its own.
    static func moduleName(ofPath path: String) -> String? {
        let components = path.components(separatedBy: "/")
        guard let index = components.lastIndex(of: "Sources"),
              index + 1 < components.count - 1 else {
            return nil
        }
        return components[index + 1]
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
    case nothingMeasured

    var message: String {
        switch self {
        case .unreadableSource(let url):
            return "Unable to read source file: \(url.path)"
        case .nothingMeasured:
            return "The coverage report measured nothing — no method could be scored. "
                + "Check that the package's tests ran and that its coverage export succeeded."
        }
    }
}

/// How much of each module the coverage report actually measured.
struct ModuleMeasurement {

    private struct Tally {
        var methodCount = 0
        var measuredFiles = 0
    }

    private var tallies: [String: Tally] = [:]

    mutating func record(module: String?, methodCount: Int, isMeasured: Bool) {
        guard let module, methodCount > 0 else {
            // A file with no methods has no code to score, so it proves nothing either way —
            // a declarations-only file is not evidence of an incomplete report.
            return
        }
        var tally = tallies[module] ?? Tally()
        tally.methodCount += methodCount
        if isMeasured {
            tally.measuredFiles += 1
        }
        tallies[module] = tally
    }

    /// Whether **any** module was measured. `false` with methods in hand means the report carries no
    /// record of anything analyzed, which is a broken export rather than code nothing links.
    var hasMeasuredAnyModule: Bool {
        tallies.values.contains { $0.measuredFiles > 0 }
    }

    /// Modules that have scoreable methods but **no file** in the report — nothing in them was
    /// linked into a test binary. Sorted, so the warning reads the same on every run.
    var unmeasuredModules: [String] {
        tallies
            .filter { $0.value.methodCount > 0 && $0.value.measuredFiles == 0 }
            .keys
            .sorted()
    }
}
