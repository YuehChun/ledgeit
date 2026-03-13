import Foundation
import ZIPFoundation
import os.log

private let exportLogger = Logger(subsystem: "com.ledgeit.app", category: "AgentMemoryExporter")

enum AgentMemoryExporter {

    // MARK: - Export

    static func exportToZip(fileManager: AgentFileManager) throws -> URL {
        let baseDir = fileManager.baseDir
        let fm = FileManager.default

        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let zipName = "LedgeIt-Memory-\(dateFmt.string(from: Date())).zip"
        let zipPath = tempDir.appendingPathComponent(zipName)

        // Copy to temp excluding cache, then zip
        let agentCopy = tempDir.appendingPathComponent("agent")
        try copyDirectory(from: baseDir, to: agentCopy, excluding: [".embedding-cache.json"])
        try fm.zipItem(at: agentCopy, to: zipPath, shouldKeepParent: true, compressionMethod: .deflate)

        exportLogger.info("Memory exported to \(zipPath.path)")
        return zipPath
    }

    // MARK: - Import

    static func importFromZip(url: URL, fileManager: AgentFileManager) throws {
        let fm = FileManager.default
        let baseDir = fileManager.baseDir

        // Unzip using ZIPFoundation (pure Swift, no Process/shell)
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try fm.unzipItem(at: url, to: tempDir)

        // Find the root: look for PERSONA.md at various locations
        let sourceDir: URL
        if fm.fileExists(atPath: tempDir.appendingPathComponent("PERSONA.md").path) {
            sourceDir = tempDir
        } else if fm.fileExists(atPath: tempDir.appendingPathComponent("agent/PERSONA.md").path) {
            sourceDir = tempDir.appendingPathComponent("agent")
        } else {
            // Scan one level deep
            let contents = (try? fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)) ?? []
            if let dir = contents.first(where: { fm.fileExists(atPath: $0.appendingPathComponent("PERSONA.md").path) }) {
                sourceDir = dir
            } else {
                throw ExportError.invalidArchive
            }
        }

        // Backup current
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let backupDir = baseDir.deletingLastPathComponent().appendingPathComponent("agent.backup-\(dateFmt.string(from: Date()))")
        if fm.fileExists(atPath: baseDir.path) {
            try fm.copyItem(at: baseDir, to: backupDir)
        }

        // Replace
        do {
            if fm.fileExists(atPath: baseDir.path) {
                try fm.removeItem(at: baseDir)
            }
            try fm.copyItem(at: sourceDir, to: baseDir)

            // Delete embedding cache (needs rebuild)
            let cachePath = baseDir.appendingPathComponent("memory/.embedding-cache.json")
            try? fm.removeItem(at: cachePath)

            exportLogger.info("Memory imported successfully from \(url.lastPathComponent)")

            // Clean up backup on success
            try? fm.removeItem(at: backupDir)
        } catch {
            // Restore from backup
            exportLogger.error("Import failed, restoring backup: \(error.localizedDescription)")
            try? fm.removeItem(at: baseDir)
            try? fm.moveItem(at: backupDir, to: baseDir)
            throw error
        }

        // Clean up temp
        try? fm.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    private static func copyDirectory(from source: URL, to destination: URL, excluding: [String]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        guard let contents = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { return }

        for item in contents {
            if excluding.contains(item.lastPathComponent) { continue }

            var isDir: ObjCBool = false
            fm.fileExists(atPath: item.path, isDirectory: &isDir)

            let dest = destination.appendingPathComponent(item.lastPathComponent)
            if isDir.boolValue {
                try copyDirectory(from: item, to: dest, excluding: excluding)
            } else {
                try fm.copyItem(at: item, to: dest)
            }
        }
    }

    enum ExportError: LocalizedError {
        case zipFailed
        case unzipFailed
        case invalidArchive

        var errorDescription: String? {
            switch self {
            case .zipFailed: return "Failed to create ZIP archive"
            case .unzipFailed: return "Failed to extract ZIP archive"
            case .invalidArchive: return "Invalid memory archive: PERSONA.md not found"
            }
        }
    }
}
