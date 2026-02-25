import Foundation

enum JSONParser {
    /// Robust JSON parsing with 5-stage recovery (ported from Python parse_json_robust)
    static func parse<T: Decodable>(_ text: String, as type: T.Type) -> T? {
        // Stage 1: Direct parse
        if let data = text.data(using: .utf8),
           let result = try? JSONDecoder().decode(type, from: data) {
            return result
        }

        // Stage 2: Extract JSON from markdown code block
        if let extracted = extractFromCodeBlock(text),
           let data = extracted.data(using: .utf8),
           let result = try? JSONDecoder().decode(type, from: data) {
            return result
        }

        // Stage 3: Find first { ... } or [ ... ] block
        if let extracted = extractJSONBlock(text),
           let data = extracted.data(using: .utf8),
           let result = try? JSONDecoder().decode(type, from: data) {
            return result
        }

        // Stage 4: Fix common JSON issues and retry
        let cleaned = fixCommonIssues(text)
        if let data = cleaned.data(using: .utf8),
           let result = try? JSONDecoder().decode(type, from: data) {
            return result
        }

        // Stage 5: Extract from code block + fix issues
        if let extracted = extractFromCodeBlock(text) ?? extractJSONBlock(text) {
            let cleaned = fixCommonIssues(extracted)
            if let data = cleaned.data(using: .utf8),
               let result = try? JSONDecoder().decode(type, from: data) {
                return result
            }
        }

        return nil
    }

    /// Parse JSON string to raw dictionary
    static func parseDict(_ text: String) -> [String: Any]? {
        let jsonString = extractFromCodeBlock(text) ?? extractJSONBlock(text) ?? text
        let cleaned = fixCommonIssues(jsonString)
        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    private static func extractFromCodeBlock(_ text: String) -> String? {
        let pattern = #"```(?:json)?\s*\n?([\s\S]*?)\n?```"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractJSONBlock(_ text: String) -> String? {
        // Find matching braces or brackets
        for opener: Character in ["{", "["] {
            let closer: Character = opener == "{" ? "}" : "]"
            guard let startIdx = text.firstIndex(of: opener) else { continue }

            var depth = 0
            var inString = false
            var escaped = false

            for idx in text.indices[startIdx...] {
                let char = text[idx]
                if escaped {
                    escaped = false
                    continue
                }
                if char == "\\" {
                    escaped = true
                    continue
                }
                if char == "\"" {
                    inString.toggle()
                    continue
                }
                if inString { continue }
                if char == opener { depth += 1 }
                if char == closer {
                    depth -= 1
                    if depth == 0 {
                        return String(text[startIdx...idx])
                    }
                }
            }
        }
        return nil
    }

    private static func fixCommonIssues(_ text: String) -> String {
        var result = text

        // Remove trailing commas before } or ]
        result = result.replacingOccurrences(
            of: #",\s*([}\]])"#,
            with: "$1",
            options: .regularExpression
        )

        // Replace single quotes with double quotes (outside of strings)
        // Simple approach: replace ' with " if it's likely a JSON key/value delimiter
        if !result.contains("\"") && result.contains("'") {
            result = result.replacingOccurrences(of: "'", with: "\"")
        }

        // Remove comments (// style)
        result = result.replacingOccurrences(
            of: #"//[^\n]*"#,
            with: "",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
