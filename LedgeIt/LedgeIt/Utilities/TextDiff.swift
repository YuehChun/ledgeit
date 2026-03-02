import Foundation

enum DiffLineType {
    case unchanged, added, removed
}

struct DiffLine: Identifiable {
    let id = UUID()
    let type: DiffLineType
    let text: String
}

struct TextDiff {
    static func diff(old: String, new: String) -> [DiffLine] {
        let oldLines = old.components(separatedBy: .newlines)
        let newLines = new.components(separatedBy: .newlines)

        let m = oldLines.count
        let n = newLines.count

        // LCS table
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...max(m, 1) {
            guard i <= m else { break }
            for j in 1...max(n, 1) {
                guard j <= n else { break }
                if oldLines[i - 1] == newLines[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to produce diff
        var result: [DiffLine] = []
        var i = m, j = n
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && oldLines[i - 1] == newLines[j - 1] {
                result.append(DiffLine(type: .unchanged, text: oldLines[i - 1]))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                result.append(DiffLine(type: .added, text: newLines[j - 1]))
                j -= 1
            } else if i > 0 {
                result.append(DiffLine(type: .removed, text: oldLines[i - 1]))
                i -= 1
            }
        }

        return result.reversed()
    }
}
