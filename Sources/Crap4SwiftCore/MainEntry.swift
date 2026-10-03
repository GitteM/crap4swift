import Foundation

enum Main {

    static func run(_ args: [String],
                    projectRoot: URL,
                    out: @escaping (String) -> Void,
                    err: @escaping (String) -> Void,
                    coverageRunner: CoverageRunner? = nil) throws -> Int32 {
        let runner = coverageRunner ?? CoverageRunner(executor: ProcessCommandExecutor())
        return try CliApplication(projectRoot: projectRoot, out: out, err: err, coverageRunner: runner).execute(args)
    }

    static func usage() -> String {
        """
        Usage:
          crap4swift            Analyze all Swift files under Sources/
          crap4swift --changed  Analyze changed Swift files under Sources/
          crap4swift <path...>  Analyze files, or for directory args analyze <dir>/Sources/**/*.swift
          crap4swift --help     Print this help message

        """
    }

    static func maxCrap(_ metrics: [MethodMetrics]) -> Double {
        var maximum = 0.0
        for metric in metrics {
            if let score = metric.crapScore {
                maximum = Swift.max(maximum, score)
            }
        }
        return maximum
    }
}

/// Public entry point used by the `crap4swift` executable.
public enum Crap4Swift {

    public static func run(_ args: [String],
                           projectRoot: URL,
                           out: @escaping (String) -> Void,
                           err: @escaping (String) -> Void) -> Int32 {
        do {
            return try Main.run(args, projectRoot: projectRoot, out: out, err: err)
        } catch {
            err(CliApplication.message(for: error) + "\n")
            return 1
        }
    }
}
