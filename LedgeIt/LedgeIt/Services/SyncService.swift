import Foundation
import GRDB
import Observation
import os

@Observable
@MainActor
final class SyncService {
    let database: AppDatabase
    private var gmailService: GmailService?

    var isSyncing: Bool = false
    var syncProgress: String = ""
    var lastError: String?

    private let logger = Logger(subsystem: "com.ledgeit", category: "SyncService")

    init(database: AppDatabase) {
        self.database = database
    }

    func configure(accessTokenProvider: @escaping @Sendable () async throws -> String) {
        self.gmailService = GmailService(accessTokenProvider: accessTokenProvider)
    }

    // MARK: - Initial Sync

    func performInitialSync(lookbackDays: Int = 30) async throws {
        guard let gmailService else {
            throw SyncServiceError.notConfigured
        }

        isSyncing = true
        syncProgress = "Starting initial sync..."
        lastError = nil

        defer {
            isSyncing = false
        }

        do {
            // Build date query
            let calendar = Calendar.current
            let lookbackDate = calendar.date(byAdding: .day, value: -lookbackDays, to: Date())!
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/MM/dd"
            let dateString = formatter.string(from: lookbackDate)
            let query = "after:\(dateString)"

            // List all messages with pagination
            syncProgress = "Fetching message list..."
            let messageRefs = try await fetchAllMessageRefs(gmailService: gmailService, query: query)

            if messageRefs.isEmpty {
                syncProgress = "No messages found."
                try updateSyncState(newEmailCount: 0)
                return
            }

            syncProgress = "Found \(messageRefs.count) messages. Fetching details..."

            // Fetch full message details with bounded concurrency
            let db = database
            let totalCount = messageRefs.count
            var processedCount = 0

            await withTaskGroup(of: Void.self) { group in
                var active = 0
                for ref in messageRefs {
                    if active >= 5 {
                        await group.next()
                        active -= 1
                    }

                    let emailId = ref.id
                    group.addTask { [gmailService] in
                        do {
                            try await self.fetchAndStoreMessage(
                                gmailService: gmailService,
                                messageId: emailId,
                                database: db
                            )
                        } catch {
                            self.logger.error("Failed to fetch message \(emailId): \(error.localizedDescription)")
                        }
                    }
                    active += 1
                    processedCount += 1

                    if processedCount % 10 == 0 || processedCount == totalCount {
                        syncProgress = "Processing \(processedCount)/\(totalCount) messages..."
                    }
                }
                await group.waitForAll()
            }

            try updateSyncState(newEmailCount: messageRefs.count)
            syncProgress = "Sync complete. \(messageRefs.count) messages synced."
            logger.info("Initial sync completed: \(messageRefs.count) messages")

        } catch {
            lastError = error.localizedDescription
            logger.error("Initial sync failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Incremental Sync

    func performIncrementalSync() async throws {
        guard let gmailService else {
            throw SyncServiceError.notConfigured
        }

        isSyncing = true
        syncProgress = "Starting incremental sync..."
        lastError = nil

        defer {
            isSyncing = false
        }

        do {
            let syncState = try getSyncState()

            // Build query from last sync date, or fall back to 7 days
            let query: String
            if let lastSync = syncState.lastSyncDate {
                query = "after:\(lastSync)"
            } else {
                let calendar = Calendar.current
                let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy/MM/dd"
                query = "after:\(formatter.string(from: weekAgo))"
            }

            syncProgress = "Fetching new messages..."
            let messageRefs = try await fetchAllMessageRefs(gmailService: gmailService, query: query)

            if messageRefs.isEmpty {
                syncProgress = "No new messages."
                return
            }

            syncProgress = "Found \(messageRefs.count) messages. Fetching details..."

            let db = database
            let totalCount = messageRefs.count
            var processedCount = 0

            await withTaskGroup(of: Void.self) { group in
                var active = 0
                for ref in messageRefs {
                    if active >= 5 {
                        await group.next()
                        active -= 1
                    }

                    let emailId = ref.id
                    group.addTask { [gmailService] in
                        do {
                            try await self.fetchAndStoreMessage(
                                gmailService: gmailService,
                                messageId: emailId,
                                database: db
                            )
                        } catch {
                            self.logger.error("Failed to fetch message \(emailId): \(error.localizedDescription)")
                        }
                    }
                    active += 1
                    processedCount += 1

                    if processedCount % 10 == 0 || processedCount == totalCount {
                        syncProgress = "Processing \(processedCount)/\(totalCount) messages..."
                    }
                }
                await group.waitForAll()
            }

            try updateSyncState(newEmailCount: messageRefs.count)
            syncProgress = "Incremental sync complete. \(messageRefs.count) messages synced."
            logger.info("Incremental sync completed: \(messageRefs.count) messages")

        } catch {
            lastError = error.localizedDescription
            logger.error("Incremental sync failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Sync State

    func getSyncState() throws -> SyncState {
        try database.db.read { db in
            try SyncState.fetchOne(db, key: 1) ?? SyncState()
        }
    }

    // MARK: - Private Helpers

    private nonisolated func fetchAllMessageRefs(
        gmailService: GmailService,
        query: String
    ) async throws -> [GmailMessageRef] {
        var allRefs: [GmailMessageRef] = []
        var pageToken: String? = nil

        repeat {
            let result = try await gmailService.listMessages(
                query: query,
                maxResults: 100,
                pageToken: pageToken
            )
            if let messages = result.messages {
                allRefs.append(contentsOf: messages)
            }
            pageToken = result.nextPageToken
        } while pageToken != nil

        return allRefs
    }

    private nonisolated func fetchAndStoreMessage(
        gmailService: GmailService,
        messageId: String,
        database: AppDatabase
    ) async throws {
        let message = try await gmailService.getMessage(id: messageId)

        // Extract headers
        let headers = message.payload?.headers ?? []
        let extracted = await gmailService.extractHeaders(from: headers)

        // Extract body
        var bodyText: String? = nil
        var bodyHtml: String? = nil
        if let payload = message.payload {
            let body = await gmailService.extractBody(from: payload)
            bodyText = body.text
            bodyHtml = body.html
        }

        // Build Email record
        let formatter = ISO8601DateFormatter()
        let createdAt = formatter.string(from: Date())

        let email = Email(
            id: message.id,
            threadId: message.threadId,
            subject: extracted.subject,
            sender: extracted.sender,
            date: extracted.date,
            snippet: message.snippet,
            bodyText: bodyText,
            bodyHtml: bodyHtml,
            labels: message.labelIds?.joined(separator: ","),
            isFinancial: false,
            isProcessed: false,
            classificationResult: nil,
            createdAt: createdAt
        )

        try await database.db.write { db in
            // Use INSERT OR IGNORE to preserve existing processed emails.
            // save() would overwrite isProcessed/isFinancial/classificationResult,
            // destroying processing results on every incremental sync.
            if try Email.fetchOne(db, key: email.id) == nil {
                try email.insert(db)
            }
        }

        // Process PDF attachments
        if let payload = message.payload {
            try await processAttachments(
                gmailService: gmailService,
                payload: payload,
                messageId: message.id,
                database: database
            )
        }
    }

    private nonisolated func processAttachments(
        gmailService: GmailService,
        payload: GmailPayload,
        messageId: String,
        database: AppDatabase
    ) async throws {
        let attachmentParts = collectAttachmentParts(from: payload)

        for part in attachmentParts {
            guard let attachmentId = part.body?.attachmentId else { continue }

            let isPDF = part.mimeType?.lowercased() == "application/pdf"

            var extractedText: String? = nil
            if isPDF {
                do {
                    let data = try await gmailService.getAttachment(
                        messageId: messageId,
                        attachmentId: attachmentId
                    )
                    extractedText = PDFParserService.extractText(from: data)
                } catch {
                    // Log but don't fail the entire sync for a single attachment
                }
            }

            let attachment = Attachment(
                id: nil,
                emailId: messageId,
                filename: part.filename,
                mimeType: part.mimeType,
                size: part.body?.size,
                gmailAttachmentId: attachmentId,
                extractedText: extractedText,
                isProcessed: isPDF && extractedText != nil
            )

            try await database.db.write { [attachment] db in
                try attachment.insert(db)
            }
        }
    }

    private nonisolated func collectAttachmentParts(from payload: GmailPayload) -> [GmailPayload] {
        var results: [GmailPayload] = []

        if let attachmentId = payload.body?.attachmentId,
           !attachmentId.isEmpty,
           let filename = payload.filename,
           !filename.isEmpty {
            results.append(payload)
        }

        if let parts = payload.parts {
            for part in parts {
                results.append(contentsOf: collectAttachmentParts(from: part))
            }
        }

        return results
    }

    private func updateSyncState(newEmailCount: Int) throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        let todayString = formatter.string(from: Date())

        try database.db.write { db in
            var state = try SyncState.fetchOne(db, key: 1) ?? SyncState()
            state.lastSyncDate = todayString
            state.totalEmailsSynced += newEmailCount
            try state.save(db)
        }
    }
}

// MARK: - Errors

enum SyncServiceError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "SyncService is not configured. Call configure(accessTokenProvider:) first."
        }
    }
}
