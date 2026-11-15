import Foundation

final class CliApplication {

    private let projectRoot: URL
    private let out: (String) -> Void
    private let err: (String) -> Void
    private let coverageRunner: CoverageRunner

    init(projectRoot: URL,
         out: @escaping (String) -> Void,
         err: @escaping (String) -> Void,
         coverageRunner: CoverageRunner) {
        self.projectRoot = projectRoot.standardizedFileURL
        self.out = out
        self.err = err
        self.coverageRunner = coverageRunner
    }

    func execute(_ args: [String]) throws -> Int32 {
        let parsed: CliArguments
        do {
            parsed = try CliArgumentsParser.parse(args)
        } catch {
            err(CliApplication.message(for: error) + "\n")
            out(Main.usage())
            return 1
        }

        if parsed.mode == .help {
            out(Main.usage())
            return 0
        }

        if parsed.mode == .version {
            out("crap4swift \(Main.version)\n")
            return 0
        }

        let filesToAnalyze = try filesForMode(parsed)
        if filesToAnalyze.isEmpty {
            out("No Swift files to analyze.\n")
            return 0
        }

        let analysis = try analyzeByModule(filesToAnalyze)
        out(ReportFormatter.format(analysis.metrics))

        if !analysis.unmeasuredModules.isEmpty {
            err(CliApplication.unmeasuredWarning(analysis.unmeasuredModules))
        }

        let maximum = Main.maxCrap(analysis.metrics)
        if CliApplication.thresholdExceeded(maximum) {
            err(String(format: "CRAP threshold exceeded: %.1f > 8.0\n", maximum))
            return 2
        }
        return 0
    }

    /// Said out loud, because a method with no coverage scores nothing and is compared with no
    /// threshold. Measured 2026-11-15: `Mocks` (`#if DEBUG`, used by other packages' tests) and
    /// `ServiceProtocols` (one extension method its package's tests never call) are both legitimately
    /// absent from their package's export — no test binary links them — so this is a warning, not a
    /// failure. A report that measured **nothing** is the failure (`CrapAnalyzerError.nothingMeasured`).
    static func unmeasuredWarning(_ modules: [String]) -> String {
        let names = modules.joined(separator: ", ")
        return "Warning: no coverage for module(s) \(names) — no test binary of this package links "
            + "their code, so their methods score N/A and are not compared with the threshold.\n"
    }

    static func thresholdExceeded(_ maximum: Double) -> Bool {
        maximum > 8.0
    }

    // MARK: - File selection

    private func filesForMode(_ parsed: CliArguments) throws -> [URL] {
        switch parsed.mode {
        case .allSources:
            return SourceFileFinder.findAllSwiftFilesUnderSources(projectRoot)
        case .changedSources:
            return try ChangedFileDetector.changedSwiftFilesUnderSources(projectRoot: projectRoot)
        case .explicitFiles:
            return try explicitFiles(parsed.fileArgs)
        case .help:
            return []
        case .version:
            return []
        }
    }

    private func explicitFiles(_ args: [String]) throws -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for arg in args {
            let url = projectRoot.appendingPathComponent(arg).standardizedFileURL
            if CliApplication.isDirectory(url) {
                for file in SourceFileFinder.findAllSwiftFilesUnderSources(url) where !seen.contains(file.path) {
                    seen.insert(file.path)
                    result.append(file)
                }
            } else if !seen.contains(url.path) {
                seen.insert(url.path)
                result.append(url)
            }
        }
        result.sort { $0.path < $1.path }
        return result
    }

    // MARK: - Module grouping

    static func moduleRootFor(workspaceRoot: URL, file: URL) -> URL {
        let root = workspaceRoot.standardizedFileURL
        var current: URL? = isDirectory(file)
            ? file.standardizedFileURL
            : file.standardizedFileURL.deletingLastPathComponent()

        while let directory = current, directory.path.hasPrefix(root.path) {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            if directory.path == root.path {
                break
            }
            current = directory.deletingLastPathComponent()
        }
        return root
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func groupByModuleRoot(_ files: [URL]) -> [(moduleRoot: URL, files: [URL])] {
        var order: [URL] = []
        var grouped: [String: (root: URL, files: [URL])] = [:]

        for file in files {
            let moduleRoot = CliApplication.moduleRootFor(workspaceRoot: projectRoot, file: file)
            let key = moduleRoot.path
            if grouped[key] == nil {
                grouped[key] = (root: moduleRoot, files: [])
                order.append(moduleRoot)
            }
            grouped[key]!.files.append(file)
        }

        return order.map { (moduleRoot: $0, files: grouped[$0.path]!.files) }
    }

    private func analyzeByModule(_ filesToAnalyze: [URL]) throws -> CrapAnalyzer.Result {
        var result = CrapAnalyzer.Result(metrics: [], unmeasuredModules: [])
        for group in groupByModuleRoot(filesToAnalyze) {
            try coverageRunner.generateCoverage(moduleRoot: group.moduleRoot)

            let coverageJSON = CoverageRunner.codecovJSON(in: group.moduleRoot)
            if coverageJSON == nil {
                err("Warning: Swift coverage JSON not found under \(group.moduleRoot.path)/.build. Coverage will be N/A.\n")
            }

            let analysis = try CrapAnalyzer.analyze(
                projectRoot: group.moduleRoot,
                files: group.files,
                coverageJSON: coverageJSON
            )
            result = CrapAnalyzer.Result(
                metrics: result.metrics + analysis.metrics,
                unmeasuredModules: result.unmeasuredModules + analysis.unmeasuredModules
            )
        }
        return result
    }

    // MARK: - Errors

    static func message(for error: Error) -> String {
        switch error {
        case let error as CliParseError:
            return error.message
        case let error as CoverageRunnerError:
            return error.message
        case let error as CrapAnalyzerError:
            return error.message
        case let error as LlvmCoverageParserError:
            return error.message
        case let error as ChangedFileDetectorError:
            return error.message
        default:
            return "\(error)"
        }
    }
}
