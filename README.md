# crap4swift

`crap4swift` is a standalone CRAP metric tool for Swift projects, modeled after `crap4java`.

It combines function cyclomatic complexity with llvm-cov function coverage and reports CRAP scores.
On each run it deletes stale coverage artifacts, runs coverage, then analyzes the selected files.

## Formula

`CRAP = CC^2 * (1 - coverage)^3 + CC`

- `CC` is estimated cyclomatic complexity.
- `coverage` is function region coverage from SwiftPM's llvm-cov JSON report.

## Coverage Pipeline

For each invocation:

1. Delete stale coverage artifacts (`<module>/.build/**/codecov/`).
2. Run `swift test --enable-code-coverage` in the owning package.
3. Read the codecov JSON report (`<module>/.build/**/codecov/*.json`).
4. Analyze selected Swift files.

## Build and Test

```bash
swift build
swift test
```

## Run

From the package root you want to analyze:

```bash
swift run crap4swift
```

## CLI

```text
--help                Print usage to stdout
(no args)             Analyze all Swift files under Sources/
--changed             Analyze changed Swift files under Sources/
<file ...>            Analyze only these files
<directory ...>       Analyze all Swift files under each directory's Sources/ subtree
```

Examples:

```bash
swift run crap4swift --help
swift run crap4swift
swift run crap4swift --changed
swift run crap4swift Sources/App/Sample.swift
swift run crap4swift Packages/A Packages/B
```

## Exit codes

- `0` success, threshold respected
- `1` invalid CLI usage
- `2` CRAP threshold exceeded (`> 8.0`)

## Notes

- If a codecov JSON report is missing, coverage is reported as `N/A`.
- Report output is sorted by CRAP descending, with `N/A` at the bottom.
- Method discovery is a token-based estimate: it counts `if`, `guard`, `for`,
  `while`, `catch`, `case`/`default`, `&&`, `||`, `??` and ternaries inside a
  function body, and ignores comments, string literals, initializers, and
  nested (local) functions.
