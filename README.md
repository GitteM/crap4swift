# crap4swift

`crap4swift` is a standalone CRAP metric tool for Swift projects, modeled after `crap4java`.

It combines function cyclomatic complexity with llvm-cov function coverage and reports CRAP scores.
On each run it deletes stale coverage artifacts, runs coverage, then analyzes the selected files.

## Credits

This project was inspired by [crap4java](https://github.com/unclebob/crap4java) by
[Robert C. Martin (Uncle Bob)](https://github.com/unclebob). `crap4swift` is a Swift
take on that same idea.

Thanks to Uncle Bob for the original tool and for making it available.

## Formula

`CRAP = CC^2 * (1 - coverage)^3 + CC`

- `CC` is estimated cyclomatic complexity.
- `coverage` is function region coverage from `llvm-cov`'s JSON export, taken across every
  test binary (see *Coverage Pipeline*).

## Coverage Pipeline

For each invocation:

1. Delete stale coverage artifacts (`<module>/.build/**/codecov/`).
2. Run `swift test --enable-code-coverage` in the owning package, on the **default** build system.
3. Export the coverage report itself: `xcrun llvm-cov export -instr-profile <codecov>/default.profdata
   <first test binary> -object <next> …`, written to `<codecov>/crap4swift-coverage.json`.
4. Analyze selected Swift files against that report.

**Step 3 is not optional.** SwiftPM's own `codecov/*.json` export is partial: measured 2026-11-15 on
Swift 6.4.2 it named 3 of 9 test bundles and omitted three whole targets, so their methods had no
coverage, printed `N/A`, and scored nothing — and a nil score is never compared with the threshold,
so the run passed. Exporting every test binary fixes it; the extra binaries must be passed with
`-object` (positional arguments also drop modules: 16 reported against 19).

A module with scoreable code that contributes nothing to the report is **named on stderr** as a
warning, because its methods score `N/A` and a nil score is never compared with the threshold. It is
not a failure: measured 2026-11-15, `Mocks` (a `#if DEBUG` target used by other packages' tests) and
`ServiceProtocols` (one extension method its own package's tests never call) are both legitimately
absent from their package's export, because no test binary links them. What *is* a failure is a
report that measured nothing at all — that is a broken export, and it fails.

The build system is deliberately the default. `--build-system native` aggregates completely but the
toolchain deprecates it, and its build never runs `actool`, so a package whose tests read a compiled
asset catalogue fails every one of those assertions.

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
--version             Print the tool's version (`crap4swift <x.y.z>`)
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
- `1` invalid CLI usage, an unreadable source, or a coverage report with no data for a module
- `2` CRAP threshold exceeded (`> 8.0`)

## Notes

- If a codecov JSON report is missing, coverage is reported as `N/A`.
- Report output is sorted by CRAP descending, with `N/A` at the bottom.
- Method discovery is a token-based estimate: it counts `if`, `guard`, `for`,
  `while`, `catch`, `case`/`default`, `&&`, `||`, `??` and ternaries inside a
  function body, and ignores comments, string literals, initializers, and
  nested (local) functions.
