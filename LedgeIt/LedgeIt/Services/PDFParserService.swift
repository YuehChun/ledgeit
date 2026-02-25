import Foundation
import PDFKit

enum PDFParserService {

    /// Extract text content from PDF data.
    /// Returns nil if the data is not a valid PDF or contains no extractable text.
    static func extractText(from data: Data) -> String? {
        guard let document = PDFDocument(data: data) else {
            return nil
        }

        let pageCount = document.pageCount
        guard pageCount > 0 else { return nil }

        var allText = ""
        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }
            if let pageText = page.string {
                if !allText.isEmpty {
                    allText.append("\n")
                }
                allText.append(pageText)
            }
        }

        let trimmed = allText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }

        if isGarbageText(trimmed) {
            return nil
        }

        return trimmed
    }

    /// Check if the extracted text is garbage (e.g., CID font encoding artifacts
    /// or mostly non-printable characters).
    static func isGarbageText(_ text: String) -> Bool {
        if text.isEmpty { return true }

        // Check for CID font garbage: (cid:NNN) patterns
        let cidCharacterCount: Int
        if let cidRegex = try? NSRegularExpression(pattern: #"\(cid:\d+\)"#) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = cidRegex.matches(in: text, range: range)
            cidCharacterCount = matches.reduce(0) { $0 + $1.range.length }
        } else {
            cidCharacterCount = 0
        }
        let cidRatio = Double(cidCharacterCount) / Double(text.count)
        if cidRatio > 0.01 {
            return true
        }

        // Check if text is mostly non-printable characters
        let printableCount = text.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || CharacterSet.whitespaces.contains(scalar)
                || CharacterSet.punctuationCharacters.contains(scalar)
        }.count

        let printableRatio = Double(printableCount) / Double(text.unicodeScalars.count)
        if printableRatio < 0.5 {
            return true
        }

        return false
    }
}
