enum CrapScore {

    static func calculate(complexity: Int, coveragePercent: Double?) -> Double? {
        guard let coveragePercent else {
            return nil
        }
        let cc = Double(complexity)
        let uncovered = 1.0 - (coveragePercent / 100.0)
        return (cc * cc * uncovered * uncovered * uncovered) + cc
    }
}
