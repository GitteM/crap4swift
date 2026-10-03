# crap4swift Specification

## 1. Purpose

`crap4swift` is a CRAP metric analyzer for Swift projects built with the
Swift Package Manager.

It shall:

- locate Swift source files to analyze
- generate llvm-cov coverage for the owning package of each analyzed file set
- parse Swift functions and estimate cyclomatic complexity
- combine complexity and coverage into CRAP scores
- print a tabular report sorted by worst score first
- fail when the maximum CRAP score exceeds the configured threshold

`crap4swift` is intended as a project-quality gate rather than a mutation tool.

## 2. Scope

This specification defines:

- the command-line contract
- source file selection rules
- coverage generation behavior
- function parsing behavior
- CRAP score computation
- report ordering and exit codes

This specification does not define:

- non-SwiftPM execution
- support for non-Swift source files
- a machine-readable report format
- configurable thresholds through the CLI

## 3. Terminology

- `project root`
  The working root from which `crap4swift` is invoked.

- `module root`
  The nearest ancestor directory of an analyzed file that contains
  `Package.swift`. If none exists below the project root, the project root is
  the module root.

- `method metric`
  A single report row consisting of function identity, cyclomatic complexity,
  coverage, and CRAP score.

- `coverage N/A`
  The state where no llvm-cov JSON report was found for the module and therefore
  coverage could not be assigned to a function.

## 4. Command-Line Interface

### 4.1 Supported Forms

- `crap4swift`
- `crap4swift --changed`
- `crap4swift <path...>`
- `crap4swift --help`

### 4.2 Mode Semantics

- no arguments
  Analyze all Swift source files under `Sources/`.

- `--changed`
  Analyze changed Swift source files under `Sources/`.

- `<path...>`
  For each explicit path:
  - if it is a file, analyze that file
  - if it is a directory, analyze all Swift files under that directory's
    `Sources/` subtree

- `--help`
  Print usage text and exit successfully.

### 4.3 Invalid Usage

The tool shall exit with usage error when argument parsing fails.

The tool shall print usage text on CLI usage failure.

## 5. File Selection Rules

### 5.1 Default Source Discovery

In default mode, the tool shall analyze all `.swift` files under
`<project-root>/Sources/**`.

### 5.2 Changed-File Discovery

In `--changed` mode, the tool shall:

- invoke `git status --porcelain`
- interpret modified, added, and untracked Swift files
- retain only `.swift` files under `<project-root>/Sources/`
- sort the resulting file list in path order

### 5.3 Explicit Paths

When explicit paths are supplied:

- file paths shall be analyzed directly
- directory paths shall be expanded to `.swift` files under `<dir>/Sources/**`
- duplicates shall be removed
- the final list shall be sorted in path order

### 5.4 Empty Selection

If no Swift files are selected after expansion and filtering:

- the tool shall print `No Swift files to analyze.`
- the tool shall exit successfully

## 6. Module Grouping

The tool shall group selected files by module root before coverage generation.

The tool shall determine the module root for a file by walking upward from the
file's directory until:

- a `Package.swift` file is found, or
- the walk leaves the project root

If no nearer `Package.swift` is found, the project root shall be used as the
module root.

Coverage generation and codecov JSON lookup shall occur once per module group.

## 7. Coverage Pipeline

For each module group, the tool shall:

1. delete stale coverage artifacts
2. run `swift test --enable-code-coverage --build-system native` with SwiftPM, so the
   report is complete regardless of the package's configured build system
3. read the resulting codecov JSON report
4. analyze the selected Swift files in that module

### 7.1 Stale Artifact Cleanup

Before coverage generation, the tool shall delete stale module-local coverage
artifacts, including any `codecov` directories under `<module>/.build/`.

### 7.2 Swift Coverage Command

Coverage generation shall invoke `swift test --enable-code-coverage` against the
module root and use the resulting codecov JSON report.

### 7.3 Missing Coverage Report

If no codecov JSON report exists after coverage generation:

- the tool shall print a warning to stderr
- coverage for functions in that module shall be reported as `N/A`

## 8. Swift Function Parsing

The tool shall parse Swift source with a token-based scanner.

The parser shall identify concrete function declarations and their basic
attributes, including:

- function name
- enclosing type name
- source location
- cyclomatic complexity

The parser shall not require full semantic resolution of sibling or external
symbols in order to extract functions.

### 8.1 Exclusions

The function parser shall ignore:

- initializers (`init`) and deinitializers (`deinit`)
- functions without a body (for example protocol requirements)
- functions declared inside another function body

### 8.2 Complexity Counting

Cyclomatic complexity shall be computed from function bodies using Swift syntax
structure rather than regex-only parsing. Keywords appearing inside comments or
string literals shall not contribute.

The counted decision points are: `if`, `guard`, `for`, `while` (including the
`while` of a `repeat`/`while` loop), `catch`, `case`/`default`, `&&`, `||`,
`??`, and ternaries.

The resulting complexity shall be an integer `CC >= 1` for concrete functions.

## 9. Coverage Attribution

Coverage shall be attributed to functions by matching parsed functions to llvm-cov
coverage data.

If an exact coverage entry for a function cannot be found, the tool may use the
nearest appropriate available coverage entry according to its implemented lookup
rules.

If no usable coverage data is available for a function:

- coverage shall be reported as `N/A`
- CRAP score shall be reported as `N/A`

## 10. CRAP Formula

For functions with known coverage, CRAP shall be computed as:

`CRAP = CC^2 * (1 - coverage)^3 + CC`

Where:

- `CC` is cyclomatic complexity
- `coverage` is the function region coverage fraction in the range `0.0..1.0`

Coverage shall be derived from the executed code regions of the llvm-cov report.

## 11. Report

The tool shall print a tabular report containing, at minimum:

- function name
- type name
- cyclomatic complexity
- coverage percentage or `N/A`
- CRAP score or `N/A`

The report shall be sorted by CRAP descending.

Functions with `N/A` CRAP shall appear after functions with numeric CRAP.

## 12. Threshold

The CRAP threshold shall be `8.0`.

The tool shall determine the maximum numeric CRAP value in the result set.

If the maximum numeric CRAP value is greater than `8.0`:

- the tool shall print `CRAP threshold exceeded: <max> > 8.0` to stderr
- the tool shall exit with threshold-failure status

If no numeric CRAP values exist:

- the maximum shall be treated as `0.0`
- the threshold shall not be considered exceeded

## 13. Exit Codes

- `0`
  Successful analysis, including empty selection or all scores at or below
  threshold.

- `1`
  CLI usage error.

- `2`
  CRAP threshold exceeded.

## 14. Error Handling

The tool shall fail fast on:

- invalid command-line usage
- coverage command failure
- unreadable source files
- parser failures that prevent analysis

Warnings about a missing codecov JSON report shall not by themselves fail the
run.

## 15. Non-Goals

The current implementation is not required to support:

- configurable thresholds via CLI
- non-SwiftPM builds
- directory recursion outside `Sources/` discovery rules
- mutation analysis
- machine-readable output formats

## 16. Conformance

An implementation conforms to this specification if it satisfies the CLI, file
selection, module grouping, coverage generation, function analysis, CRAP
computation, reporting, and exit-code rules above for Swift projects built with
the Swift Package Manager.
