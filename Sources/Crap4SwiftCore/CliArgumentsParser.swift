enum CliParseError: Error, Equatable {
    case changedCannotBeCombinedWithFileArguments

    var message: String {
        switch self {
        case .changedCannotBeCombinedWithFileArguments:
            return "--changed cannot be combined with file arguments"
        }
    }
}

enum CliArgumentsParser {

    static func parse(_ args: [String]) throws -> CliArguments {
        if args.isEmpty {
            return CliArguments(mode: .allSources, fileArgs: [])
        }

        if args.contains("--help") {
            return CliArguments(mode: .help, fileArgs: [])
        }

        let changed = args.contains("--changed")
        let values = nonFlagArguments(args)
        if changed && !values.isEmpty {
            throw CliParseError.changedCannotBeCombinedWithFileArguments
        }
        if changed {
            return CliArguments(mode: .changedSources, fileArgs: [])
        }
        return CliArguments(mode: .explicitFiles, fileArgs: values)
    }

    static func nonFlagArguments(_ args: [String]) -> [String] {
        args.filter { !$0.hasPrefix("--") }
    }
}
