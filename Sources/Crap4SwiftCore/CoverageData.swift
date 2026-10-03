struct CoverageData: Equatable {
    let missedRegions: Int
    let coveredRegions: Int

    var coveragePercent: Double {
        let total = missedRegions + coveredRegions
        if total == 0 {
            return 0.0
        }
        return (Double(coveredRegions) * 100.0) / Double(total)
    }
}
