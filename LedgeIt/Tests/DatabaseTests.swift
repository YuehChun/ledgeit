import Testing
import GRDB
@testable import LedgeIt

struct DatabaseTests {

    // Helper to create an in-memory database with migrations
    private func makeTestDatabase() throws -> DatabaseQueue {
        let db = try DatabaseQueue(path: ":memory:")
        var migrator = DatabaseMigrator()
        DatabaseMigrations.registerMigrations(&migrator)
        try migrator.migrate(db)
        return db
    }

    // MARK: - Schema

    @Test func migrationCreatesAllTables() throws {
        let db = try makeTestDatabase()

        try db.read { db in
            let tables = ["emails", "transactions", "attachments", "calendar_events", "sync_state"]
            for table in tables {
                let exists = try db.tableExists(table)
                precondition(exists, "Table \(table) should exist")
            }
        }
    }

    @Test func syncStateHasInitialRow() throws {
        let db = try makeTestDatabase()

        let state = try db.read { db in
            try SyncState.fetchOne(db)
        }
        #expect(state != nil)
        #expect(state?.id == 1)
        #expect(state?.totalEmailsSynced == 0)
        #expect(state?.totalEmailsProcessed == 0)
    }

    // MARK: - Email CRUD

    @Test func insertAndFetchEmail() throws {
        let db = try makeTestDatabase()

        let email = Email(
            id: "msg_001",
            threadId: "thread_001",
            subject: "Test Subject",
            sender: "test@example.com",
            date: "2024-01-15T10:00:00Z",
            snippet: "Test snippet",
            bodyText: "Test body text",
            bodyHtml: nil,
            labels: "INBOX,UNREAD",
            isFinancial: true,
            isProcessed: false,
            classificationResult: nil,
            createdAt: "2024-01-15T10:00:00Z"
        )

        try db.write { db in
            try email.save(db)
        }

        let fetched = try db.read { db in
            try Email.fetchOne(db, key: "msg_001")
        }
        #expect(fetched != nil)
        #expect(fetched?.subject == "Test Subject")
        #expect(fetched?.sender == "test@example.com")
        #expect(fetched?.isFinancial == true)
        #expect(fetched?.isProcessed == false)
    }

    @Test func updateEmail() throws {
        let db = try makeTestDatabase()

        var email = Email(
            id: "msg_002",
            threadId: nil,
            subject: "Original",
            sender: "sender@test.com",
            date: nil,
            snippet: nil,
            bodyText: nil,
            bodyHtml: nil,
            labels: nil,
            isFinancial: false,
            isProcessed: false,
            classificationResult: nil,
            createdAt: nil
        )

        try db.write { db in
            try email.save(db)
        }

        email.isProcessed = true
        email.classificationResult = "{\"decision\":\"accept\"}"

        try db.write { db in
            try email.update(db)
        }

        let fetched = try db.read { db in
            try Email.fetchOne(db, key: "msg_002")
        }
        #expect(fetched?.isProcessed == true)
        #expect(fetched?.classificationResult == "{\"decision\":\"accept\"}")
    }

    @Test func deleteEmail() throws {
        let db = try makeTestDatabase()

        let email = Email(
            id: "msg_003",
            threadId: nil, subject: "Delete Me",
            sender: nil, date: nil, snippet: nil,
            bodyText: nil, bodyHtml: nil, labels: nil,
            isFinancial: false, isProcessed: false,
            classificationResult: nil, createdAt: nil
        )

        try db.write { db in
            try email.save(db)
        }

        try db.write { db in
            _ = try Email.deleteOne(db, key: "msg_003")
        }

        let fetched = try db.read { db in
            try Email.fetchOne(db, key: "msg_003")
        }
        #expect(fetched == nil)
    }

    // MARK: - Transaction CRUD

    @Test func insertAndFetchTransaction() throws {
        let db = try makeTestDatabase()

        let txn = Transaction(
            id: nil,
            emailId: nil,
            attachmentId: nil,
            amount: 99.99,
            currency: "USD",
            merchant: "Test Store",
            category: "SHOPPING",
            subcategory: nil,
            transactionDate: "2024-01-15",
            description: "Test purchase",
            type: "debit",
            transferType: nil,
            transferMetadata: nil,
            confidence: 0.95,
            rawExtraction: nil,
            createdAt: nil
        )

        try db.write { db in
            try txn.insert(db)
        }

        let fetched = try db.read { db in
            try Transaction.order(Transaction.Columns.id.desc).fetchOne(db)
        }
        #expect(fetched != nil)
        #expect(fetched?.amount == 99.99)
        #expect(fetched?.merchant == "Test Store")
        #expect(fetched?.category == "SHOPPING")
        #expect(fetched?.type == "debit")
    }

    @Test func transactionAutoIncrements() throws {
        let db = try makeTestDatabase()

        let txn1 = Transaction(
            id: nil, emailId: nil, attachmentId: nil,
            amount: 10.0, currency: "USD", merchant: "A",
            category: nil, subcategory: nil, transactionDate: nil,
            description: nil, type: nil, transferType: nil,
            transferMetadata: nil, confidence: nil,
            rawExtraction: nil, createdAt: nil
        )

        let txn2 = Transaction(
            id: nil, emailId: nil, attachmentId: nil,
            amount: 20.0, currency: "USD", merchant: "B",
            category: nil, subcategory: nil, transactionDate: nil,
            description: nil, type: nil, transferType: nil,
            transferMetadata: nil, confidence: nil,
            rawExtraction: nil, createdAt: nil
        )

        try db.write { db in
            try txn1.insert(db)
            try txn2.insert(db)
        }

        let all = try db.read { db in
            try Transaction.order(Transaction.Columns.id.asc).fetchAll(db)
        }
        #expect(all.count == 2)
        #expect(all[0].merchant == "A")
        #expect(all[1].merchant == "B")
        #expect(all[1].id! > all[0].id!)
    }

    // MARK: - Attachment CRUD

    @Test func insertAndFetchAttachment() throws {
        let db = try makeTestDatabase()

        let email = Email(
            id: "msg_att_001",
            threadId: nil, subject: nil, sender: nil,
            date: nil, snippet: nil, bodyText: nil,
            bodyHtml: nil, labels: nil, isFinancial: false,
            isProcessed: false, classificationResult: nil,
            createdAt: nil
        )

        try db.write { db in
            try email.save(db)
        }

        let att = Attachment(
            id: nil,
            emailId: "msg_att_001",
            filename: "invoice.pdf",
            mimeType: "application/pdf",
            size: 12345,
            gmailAttachmentId: "att_gmail_001",
            extractedText: "Invoice total: $500",
            isProcessed: true
        )

        try db.write { db in
            try att.insert(db)
        }

        let fetched = try db.read { db in
            try Attachment.order(Attachment.Columns.id.desc).fetchOne(db)
        }
        #expect(fetched != nil)
        #expect(fetched?.filename == "invoice.pdf")
        #expect(fetched?.mimeType == "application/pdf")
        #expect(fetched?.extractedText == "Invoice total: $500")
        #expect(fetched?.isProcessed == true)
    }

    // MARK: - CalendarEvent CRUD

    @Test func insertAndFetchCalendarEvent() throws {
        let db = try makeTestDatabase()

        let event = CalendarEvent(
            id: nil,
            transactionId: nil,
            googleEventId: nil,
            title: "Netflix Payment",
            date: "2024-02-01",
            amount: 15.99,
            isSynced: false
        )

        try db.write { db in
            try event.insert(db)
        }

        let fetched = try db.read { db in
            try CalendarEvent.order(CalendarEvent.Columns.id.desc).fetchOne(db)
        }
        #expect(fetched != nil)
        #expect(fetched?.title == "Netflix Payment")
        #expect(fetched?.amount == 15.99)
        #expect(fetched?.isSynced == false)
    }

    // MARK: - SyncState

    @Test func updateSyncState() throws {
        let db = try makeTestDatabase()

        try db.write { db in
            if var state = try SyncState.fetchOne(db, key: 1) {
                state.lastSyncDate = "2024-01-15T10:00:00Z"
                state.totalEmailsSynced = 100
                state.totalEmailsProcessed = 50
                try state.update(db)
            }
        }

        let state = try db.read { db in
            try SyncState.fetchOne(db, key: 1)
        }
        #expect(state?.lastSyncDate == "2024-01-15T10:00:00Z")
        #expect(state?.totalEmailsSynced == 100)
        #expect(state?.totalEmailsProcessed == 50)
    }

    // MARK: - Queries

    @Test func filterEmailsByFinancial() throws {
        let db = try makeTestDatabase()

        try db.write { db in
            try Email(
                id: "fin_1", threadId: nil, subject: "Payment",
                sender: nil, date: nil, snippet: nil,
                bodyText: nil, bodyHtml: nil, labels: nil,
                isFinancial: true, isProcessed: false,
                classificationResult: nil, createdAt: nil
            ).save(db)

            try Email(
                id: "fin_2", threadId: nil, subject: "Newsletter",
                sender: nil, date: nil, snippet: nil,
                bodyText: nil, bodyHtml: nil, labels: nil,
                isFinancial: false, isProcessed: false,
                classificationResult: nil, createdAt: nil
            ).save(db)
        }

        let financialEmails = try db.read { db in
            try Email
                .filter(Email.Columns.isFinancial == true)
                .fetchAll(db)
        }
        #expect(financialEmails.count == 1)
        #expect(financialEmails[0].subject == "Payment")

        let allEmails = try db.read { db in
            try Email.fetchAll(db)
        }
        #expect(allEmails.count == 2)
    }

    @Test func filterTransactionsByCategory() throws {
        let db = try makeTestDatabase()

        try db.write { db in
            try Transaction(
                id: nil, emailId: nil, attachmentId: nil,
                amount: 50, currency: "USD", merchant: "Store",
                category: "SHOPPING", subcategory: nil,
                transactionDate: nil, description: nil, type: nil,
                transferType: nil, transferMetadata: nil,
                confidence: nil, rawExtraction: nil, createdAt: nil
            ).insert(db)

            try Transaction(
                id: nil, emailId: nil, attachmentId: nil,
                amount: 15, currency: "USD", merchant: "Cafe",
                category: "FOOD_AND_DRINK", subcategory: nil,
                transactionDate: nil, description: nil, type: nil,
                transferType: nil, transferMetadata: nil,
                confidence: nil, rawExtraction: nil, createdAt: nil
            ).insert(db)

            try Transaction(
                id: nil, emailId: nil, attachmentId: nil,
                amount: 30, currency: "USD", merchant: "Shop B",
                category: "SHOPPING", subcategory: nil,
                transactionDate: nil, description: nil, type: nil,
                transferType: nil, transferMetadata: nil,
                confidence: nil, rawExtraction: nil, createdAt: nil
            ).insert(db)
        }

        let shopping = try db.read { db in
            try Transaction
                .filter(Transaction.Columns.category == "SHOPPING")
                .fetchAll(db)
        }
        #expect(shopping.count == 2)

        let food = try db.read { db in
            try Transaction
                .filter(Transaction.Columns.category == "FOOD_AND_DRINK")
                .fetchAll(db)
        }
        #expect(food.count == 1)
    }
}
