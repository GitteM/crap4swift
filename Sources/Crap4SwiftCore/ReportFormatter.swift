import Foundation

enum ReportFormatter {

    private static let methodWidth = 30
    private static let classWidth = 35
    private static let complexityWidth = 4
    private static let coverageWidth = 7
    private static let crapWidth = 8

    static func format(_ entries: [MethodMetrics]) -> String {
        let sorted = CrapAnalyzer.sortByCrap(entries)

        let header = [
            pad("Method", methodWidth),
            pad("Class", classWidth),
            pad("CC", complexityWidth, right: true),
            pad("Cov%", coverageWidth, right: true),
            pad("CRAP", crapWidth, right: true)
        ].joined(separator: " ")
        let separator = String(repeating: "-", count: header.count)

        var output = "CRAP Report\n"
        output += "===========\n"
        output += header + "\n"
        output += separator + "\n"

        for entry in sorted {
            let row = [
                pad(entry.methodName, methodWidth),
                pad(entry.className, classWidth),
                pad(String(entry.complexity), complexityWidth, right: true),
                pad(formatCoverage(entry.coveragePercent), coverageWidth, right: true),
                pad(formatCrap(entry.crapScore), crapWidth, right: true)
            ].joined(separator: " ")
            output += row + "\n"
        }

        return output
    }

    static func formatCoverage(_ coverage: Double?) -> String {
        guard let coverage else {
            return "  N/A "
        }
        return String(format: "%.1f%%", coverage)
    }

    static func formatCrap(_ score: Double?) -> String {
        guard let score else {
            return "     N/A"
        }
        return String(format: "%.1f", score)
    }

    static func pad(_ value: String, _ width: Int, right: Bool = false) -> String {
        guard value.count < width else {
            return value
        }
        let padding = String(repeating: " ", count: width - value.count)
        return right ? padding + value : value + padding
    }
}
