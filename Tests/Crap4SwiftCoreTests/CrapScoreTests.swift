import XCTest
@testable import Crap4SwiftCore

final class CrapScoreTests: XCTestCase {

    func testReturnsComplexityWhenFullyCovered() {
        XCTAssertEqual(CrapScore.calculate(complexity: 5, coveragePercent: 100.0)!, 5.0, accuracy: 0.0001)
    }

    func testReturnsCcSquaredPlusCcWhenUncovered() {
        XCTAssertEqual(CrapScore.calculate(complexity: 5, coveragePercent: 0.0)!, 30.0, accuracy: 0.0001)
    }

    func testComputesPartialCoverage() {
        XCTAssertEqual(CrapScore.calculate(complexity: 8, coveragePercent: 45.0)!, 18.648, accuracy: 0.01)
    }

    func testReturnsNilForUnknownCoverage() {
        XCTAssertNil(CrapScore.calculate(complexity: 3, coveragePercent: nil))
    }
}

final class CoverageDataTests: XCTestCase {

    func testComputesPercent() {
        XCTAssertEqual(CoverageData(missedRegions: 1, coveredRegions: 3).coveragePercent, 75.0, accuracy: 0.001)
    }

    func testZeroTotalIsZeroPercent() {
        XCTAssertEqual(CoverageData(missedRegions: 0, coveredRegions: 0).coveragePercent, 0.0, accuracy: 0.001)
    }
}
