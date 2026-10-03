import XCTest
@testable import Crap4SwiftCore

final class ReportFormatterTests: XCTestCase {

    func testFormatsHeaderSeparatorAndRows() {
        let scored = MethodMetrics(methodName: "foo", className: "Sample", complexity: 3, coveragePercent: 85.0, crapScore: 4.5)
        let unknown = MethodMetrics(methodName: "bar", className: "Sample", complexity: 2, coveragePercent: nil, crapScore: nil)

        let report = ReportFormatter.format([scored, unknown])

        let header = [
            ReportFormatter.pad("Method", 30),
            ReportFormatter.pad("Class", 35),
            ReportFormatter.pad("CC", 4, right: true),
            ReportFormatter.pad("Cov%", 7, right: true),
            ReportFormatter.pad("CRAP", 8, right: true)
        ].joined(separator: " ")

        XCTAssertTrue(report.hasPrefix("CRAP Report\n===========\n\(header)\n"))
        XCTAssertTrue(report.contains(String(repeating: "-", count: header.count)))
        XCTAssertTrue(report.contains("foo"))
        XCTAssertTrue(report.contains("  85.0%"))
        XCTAssertTrue(report.contains("     4.5"))
        XCTAssertTrue(report.contains("   N/A "))
        XCTAssertTrue(report.contains("     N/A"))
    }

    func testSortsScoredEntriesAheadOfNaAndHigherScoresFirst() {
        let lower = MethodMetrics(methodName: "low", className: "Sample", complexity: 2, coveragePercent: 100.0, crapScore: 2.0)
        let unknown = MethodMetrics(methodName: "unknown", className: "Sample", complexity: 2, coveragePercent: nil, crapScore: nil)
        let higher = MethodMetrics(methodName: "high", className: "Sample", complexity: 5, coveragePercent: 10.0, crapScore: 9.0)

        let report = ReportFormatter.format([lower, unknown, higher])

        let highIndex = report.range(of: "high")!.lowerBound
        let lowIndex = report.range(of: "low")!.lowerBound
        let unknownIndex = report.range(of: "unknown")!.lowerBound
        XCTAssertTrue(highIndex < lowIndex)
        XCTAssertTrue(lowIndex < unknownIndex)
    }

    func testCoverageAndCrapFormatting() {
        XCTAssertEqual(ReportFormatter.formatCoverage(nil), "  N/A ")
        XCTAssertEqual(ReportFormatter.formatCoverage(85.0), "85.0%")
        XCTAssertEqual(ReportFormatter.formatCrap(nil), "     N/A")
        XCTAssertEqual(ReportFormatter.formatCrap(4.5), "4.5")
    }
}
