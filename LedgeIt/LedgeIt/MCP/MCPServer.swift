import Foundation
import GRDB

struct MCPServerRunner {

    // MARK: - Entry Point

    static func run() async {
        let dbPath = parseDBPath()
        guard let dbPath else {
            writeError("Usage: ledgeit-mcp --db <path-to-database>")
            return
        }

        let database: AppDatabase
        do {
            database = try AppDatabase(path: dbPath)
        } catch {
            writeError("Failed to open database at \(dbPath): \(error.localizedDescription)")
            return
        }

        let queryService = FinancialQueryService(database: database)
        let handler = MCPToolHandler(queryService: queryService)

        writeError("LedgeIt MCP server started, reading from stdin...")

        while let line = readLine() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                writeError("Invalid JSON input: \(trimmed)")
                continue
            }

            let id = json["id"]  // Can be Int, String, or nil (for notifications)
            let method = json["method"] as? String ?? ""

            await handleRequest(method: method, id: id, params: json["params"] as? [String: Any] ?? [:], handler: handler)
        }

        writeError("LedgeIt MCP server shutting down.")
    }

    // MARK: - Request Handling

    private static func handleRequest(method: String, id: Any?, params: [String: Any], handler: MCPToolHandler) async {
        switch method {
        case "initialize":
            let result: [String: Any] = [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": [:] as [String: Any]
                ] as [String: Any],
                "serverInfo": [
                    "name": "LedgeIt",
                    "version": "1.0.0"
                ] as [String: Any]
            ]
            writeResponse(id: id, result: result)

        case "notifications/initialized":
            // No response needed for notifications
            break

        case "tools/list":
            let tools = handler.toolDefinitions()
            let result: [String: Any] = ["tools": tools]
            writeResponse(id: id, result: result)

        case "tools/call":
            let toolName = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]

            do {
                let text = try await handler.handleToolCall(name: toolName, arguments: arguments)
                let result: [String: Any] = [
                    "content": [
                        ["type": "text", "text": text] as [String: Any]
                    ]
                ]
                writeResponse(id: id, result: result)
            } catch {
                let result: [String: Any] = [
                    "content": [
                        ["type": "text", "text": "Error: \(error.localizedDescription)"] as [String: Any]
                    ],
                    "isError": true
                ]
                writeResponse(id: id, result: result)
            }

        default:
            writeErrorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: - Argument Parsing

    private static func parseDBPath() -> String? {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--db"), idx + 1 < args.count else {
            return nil
        }
        return args[idx + 1]
    }

    // MARK: - JSON-RPC Output

    private static func writeResponse(id: Any?, result: [String: Any]) {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "result": result
        ]
        if let id = id {
            response["id"] = id
        }
        writeJSON(response)
    }

    private static func writeErrorResponse(id: Any?, code: Int, message: String) {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "error": [
                "code": code,
                "message": message
            ] as [String: Any]
        ]
        if let id = id {
            response["id"] = id
        }
        writeJSON(response)
    }

    private static func writeJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            writeError("Failed to serialize response JSON")
            return
        }
        print(str)
        fflush(stdout)
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("[LedgeIt MCP] \(message)\n".utf8))
    }
}
