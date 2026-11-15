import Foundation

enum CoverageRunnerError: Error, Equatable {
    case commandFailed(Int32)
    case exportFailed(Int32)

    var message: String {
        switch self {
        case .commandFailed(let exit):
            return "Coverage command failed with exit \(exit)"
        case .exportFailed(let exit):
            return "Coverage export failed with exit \(exit)"
        }
    }
}

/// The coverage products SwiftPM leaves for one package, and the binaries they must be
/// combined across.
struct CoverageExportPlan: Equatable {
    /// The directory holding `default.profdata` and every per-bundle `.profraw`.
    let codecovDirectory: URL
    /// The merged profile.
    let profileData: URL
    /// Every test bundle's executable, sorted, so the command is deterministic.
    let binaries: [URL]
}

/// Produces the coverage report the analyser reads, for one package.
///
/// **SwiftPM's own report is not usable as-is.** It writes one `*.json` under
/// `.build/**/codecov/`, and that export is partial: measured on this machine (Swift 6.4.2,
/// 2026-11-15) it named **3 of 9** test bundles and omitted whole modules — `Library`,
/// `Progressions` and `Voicing` never appeared, so `SearchModel.swift` had no coverage record
/// at all and its methods scored `N/A`. So the tool runs the tests itself and then exports the
/// coverage **itself**, from the merged profile and every test binary, with the documented
/// `llvm-cov export … -object …` form. Passing the extra binaries positionally, rather than
/// with `-object`, silently drops modules too: the same complete run reported 16 modules
/// positionally and 19 with `-object`.
///
/// The **default** build system is used. `--build-system native` was forced here previously
/// because it aggregates completely, but this toolchain deprecates it, and its build never runs
/// `actool`, so a package whose tests read a compiled asset catalogue fails every one of those
/// assertions.
final class CoverageRunner {

    /// The name of the file this tool writes, and therefore the one the analyser prefers over
    /// whatever else SwiftPM left in the same directory.
    static let exportFileName = "crap4swift-coverage.json"

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

        try writeCompleteCoverage(moduleRoot: moduleRoot)
    }

    static let coverageCommand = ["swift", "test", "--enable-code-coverage"]

    private func deleteStaleArtifacts(moduleRoot: URL) throws {
        for directory in CoverageRunner.codecovDirectories(in: moduleRoot) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    /// Exports every test bundle's coverage into one report. A package with no profile or no
    /// test bundles is left to SwiftPM's own JSON: there is nothing to combine, and the
    /// analyser fails loudly rather than scoring `N/A` when that report turns out to be
    /// incomplete.
    private func writeCompleteCoverage(moduleRoot: URL) throws {
        guard let plan = CoverageRunner.exportPlan(in: moduleRoot) else {
            return
        }
        let output = plan.codecovDirectory.appendingPathComponent(CoverageRunner.exportFileName)
        let exit = try executor.run(
            CoverageRunner.exportCommand(plan),
            directory: moduleRoot,
            writingStandardOutputTo: output
        )
        if exit != 0 {
            throw CoverageRunnerError.exportFailed(exit)
        }
    }

    // MARK: - Artifact discovery

    /// The profile and binaries to export, from the first coverage directory that has both.
    static func exportPlan(in moduleRoot: URL) -> CoverageExportPlan? {
        for directory in codecovDirectories(in: moduleRoot) {
            let profileData = directory.appendingPathComponent("default.profdata")
            guard FileManager.default.fileExists(atPath: profileData.path) else {
                continue
            }
            let binaries = xctestBinaries(inProductsOf: directory)
            guard !binaries.isEmpty else {
                continue
            }
            return CoverageExportPlan(
                codecovDirectory: directory,
                profileData: profileData,
                binaries: binaries
            )
        }
        return nil
    }

    /// `llvm-cov export` in its documented multi-binary form: the first binary positional, the
    /// rest named with `-object`.
    static func exportCommand(_ plan: CoverageExportPlan) -> [String] {
        var command = [
            "xcrun", "llvm-cov", "export",
            "-instr-profile", plan.profileData.path,
            plan.binaries[0].path,
        ]
        for binary in plan.binaries.dropFirst() {
            command.append("-object")
            command.append(binary.path)
        }
        return command
    }

    /// Every `*.xctest` bundle beside the coverage directory, as its executable. The products
    /// directory is the coverage directory's parent under both build systems
    /// (`.build/out/Products/Debug` and `.build/<triple>/debug`).
    static func xctestBinaries(inProductsOf codecovDirectory: URL) -> [URL] {
        let products = codecovDirectory.deletingLastPathComponent()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: products,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return contents
            .filter { $0.pathExtension == "xctest" }
            .sorted { $0.path < $1.path }
            .compactMap { bundle in
                let executable = bundle
                    .appendingPathComponent("Contents/MacOS")
                    .appendingPathComponent(bundle.deletingPathExtension().lastPathComponent)
                return FileManager.default.fileExists(atPath: executable.path) ? executable : nil
            }
    }

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

    /// This tool's own export when there is one, SwiftPM's report otherwise.
    static func codecovJSON(in moduleRoot: URL) -> URL? {
        for directory in codecovDirectories(in: moduleRoot) {
            let own = directory.appendingPathComponent(exportFileName)
            if FileManager.default.fileExists(atPath: own.path) {
                return own
            }
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
