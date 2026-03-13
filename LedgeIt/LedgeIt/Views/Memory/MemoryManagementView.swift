import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MemoryManagementView: View {
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }
    @AppStorage("heartbeatAutoArchive") private var autoArchiveEnabled = true

    @State private var files: [AgentFileManager.MemoryFileInfo] = []
    @State private var expandedFile: String?
    @State private var expandedContent: String = ""
    @State private var isConsolidating = false
    @State private var isReorganizing = false
    @State private var showReorgPreview = false
    @State private var reorgBefore = ""
    @State private var reorgAfter = ""
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var showDeleteConfirm = false
    @State private var fileToDelete: AgentFileManager.MemoryFileInfo?
    @State private var showImportConfirm = false
    @State private var importURL: URL?

    private let fileManager = AgentFileManager()
    private let consolidator = AgentMemoryConsolidator.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                fileBrowserSection
                actionsSection
                statsSection
            }
            .padding()
        }
        .navigationTitle(l10n.memoryManagement)
        .task { loadFiles() }
        .alert(alertMessage ?? "", isPresented: $showAlert) {
            Button("OK") {}
        }
        .alert(l10n.deleteMemoryFile, isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { performDelete() }
        } message: {
            if let file = fileToDelete {
                Text(l10n.deleteMemoryConfirm(file.fileName))
            }
        }
        .alert(l10n.importConfirmTitle, isPresented: $showImportConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Import", role: .destructive) { performImport() }
        } message: {
            Text(l10n.importConfirmMessage)
        }
        .sheet(isPresented: $showReorgPreview) {
            reorgPreviewSheet
        }
    }

    // MARK: - File Browser

    private var fileBrowserSection: some View {
        GroupBox(l10n.memoryFiles) {
            VStack(spacing: 0) {
                if files.isEmpty {
                    Text("No memory files found")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ForEach(files, id: \.fileName) { file in
                        fileRow(file)
                        if file.fileName != files.last?.fileName {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func fileRow(_ file: AgentFileManager.MemoryFileInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(file.fileName)
                    .font(.body.monospaced())
                Spacer()
                Text(formatFileSize(file.fileSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatDate(file.modifiedDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let protectedFiles = ["PERSONA.md", "USER.md"]
                if !protectedFiles.contains(file.fileName) {
                    Button(role: .destructive) {
                        fileToDelete = file
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    toggleExpand(file)
                } label: {
                    Image(systemName: expandedFile == file.fileName ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)

            if expandedFile == file.fileName {
                Text(expandedContent)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        GroupBox(l10n.memoryActions) {
            HStack(spacing: 12) {
                Button {
                    Task { await archiveLogs() }
                } label: {
                    Label(l10n.archiveOldLogs, systemImage: "archivebox")
                }
                .disabled(isConsolidating)

                Button {
                    Task { await reorganize() }
                } label: {
                    Label(l10n.reorganizeMemory, systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(isReorganizing)

                Spacer()

                Button {
                    exportMemory()
                } label: {
                    Label(l10n.exportMemory, systemImage: "square.and.arrow.up")
                }

                Button {
                    selectImportFile()
                } label: {
                    Label(l10n.importMemory, systemImage: "square.and.arrow.down")
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        GroupBox(l10n.memoryStats) {
            VStack(alignment: .leading, spacing: 8) {
                let dailyCount = files.filter { $0.fileName.count == 13 && $0.fileName.hasSuffix(".md") }.count
                let memorySize = files.first(where: { $0.fileName == "MEMORY.md" })?.fileSize ?? 0
                let totalSize = files.reduce(0) { $0 + $1.fileSize }

                LabeledContent(l10n.dailyLogCount) { Text("\(dailyCount)") }
                LabeledContent(l10n.memoryFileSize) { Text(formatFileSize(memorySize)) }
                LabeledContent(l10n.totalMemorySize) { Text(formatFileSize(totalSize)) }

                Divider()

                Toggle(l10n.autoArchive, isOn: $autoArchiveEnabled)
                Text(l10n.autoArchiveDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Reorg Preview

    private var reorgPreviewSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text(l10n.reorganizeMemory).font(.headline)
                Spacer()
                Button("Cancel") { showReorgPreview = false }
                Button(l10n.applyChanges) {
                    applyReorg()
                    showReorgPreview = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            HSplitView {
                VStack(alignment: .leading) {
                    Text(l10n.memoryBefore).font(.subheadline.bold())
                    ScrollView {
                        Text(reorgBefore)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()

                VStack(alignment: .leading) {
                    Text(l10n.memoryAfter).font(.subheadline.bold())
                    ScrollView {
                        Text(reorgAfter)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 800, minHeight: 500)
    }

    // MARK: - Actions Implementation

    private func loadFiles() {
        files = fileManager.listAllFiles()
    }

    private func toggleExpand(_ file: AgentFileManager.MemoryFileInfo) {
        if expandedFile == file.fileName {
            expandedFile = nil
        } else {
            expandedContent = (try? String(contentsOf: file.url, encoding: .utf8)) ?? "Unable to read file"
            expandedFile = file.fileName
        }
    }

    private func performDelete() {
        guard let file = fileToDelete else { return }
        try? FileManager.default.removeItem(at: file.url)
        loadFiles()
        fileToDelete = nil
    }

    private func archiveLogs() async {
        isConsolidating = true
        defer { isConsolidating = false }
        do {
            let archived = try await consolidator.consolidateIfNeeded(fileManager: fileManager)
            alertMessage = archived ? l10n.archiveComplete : "No logs to archive"
            showAlert = true
            loadFiles()
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func reorganize() async {
        isReorganizing = true
        defer { isReorganizing = false }
        do {
            let result = try await consolidator.reorganizeMemory(fileManager: fileManager)
            reorgBefore = result.before
            reorgAfter = result.after
            showReorgPreview = true
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func applyReorg() {
        do {
            try consolidator.applyReorganization(fileManager: fileManager, content: reorgAfter)
            alertMessage = l10n.reorganizeComplete
            showAlert = true
            loadFiles()
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func exportMemory() {
        do {
            let zipURL = try AgentMemoryExporter.exportToZip(fileManager: fileManager)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = zipURL.lastPathComponent
            panel.allowedContentTypes = [.zip]
            if panel.runModal() == .OK, let dest = panel.url {
                try FileManager.default.copyItem(at: zipURL, to: dest)
                alertMessage = l10n.exportSuccess
                showAlert = true
            }
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func selectImportFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            importURL = url
            showImportConfirm = true
        }
    }

    private func performImport() {
        guard let url = importURL else { return }
        do {
            try AgentMemoryExporter.importFromZip(url: url, fileManager: fileManager)
            alertMessage = l10n.memoryImportSuccess
            showAlert = true
            loadFiles()
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    // MARK: - Formatters

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}
