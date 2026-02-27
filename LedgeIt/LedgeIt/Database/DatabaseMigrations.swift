import Foundation
import GRDB

struct DatabaseMigrations {
    static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1") { db in
            // emails
            try db.create(table: "emails") { t in
                t.primaryKey("id", .text)
                t.column("thread_id", .text)
                t.column("subject", .text)
                t.column("sender", .text)
                t.column("date", .text)
                t.column("snippet", .text)
                t.column("body_text", .text)
                t.column("body_html", .text)
                t.column("labels", .text)
                t.column("is_financial", .integer).notNull().defaults(to: 0)
                t.column("is_processed", .integer).notNull().defaults(to: 0)
                t.column("classification_result", .text)
                t.column("created_at", .text).defaults(sql: "CURRENT_TIMESTAMP")
            }

            // attachments (before transactions, since transactions references it)
            try db.create(table: "attachments") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("email_id", .text).references("emails", onDelete: .none)
                t.column("filename", .text)
                t.column("mime_type", .text)
                t.column("size", .integer)
                t.column("gmail_attachment_id", .text)
                t.column("extracted_text", .text)
                t.column("is_processed", .integer).notNull().defaults(to: 0)
            }

            // transactions
            try db.create(table: "transactions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("email_id", .text).references("emails", onDelete: .none)
                t.column("attachment_id", .integer).references("attachments", onDelete: .none)
                t.column("amount", .double).notNull()
                t.column("currency", .text).notNull().defaults(to: "USD")
                t.column("merchant", .text)
                t.column("category", .text)
                t.column("subcategory", .text)
                t.column("transaction_date", .text)
                t.column("description", .text)
                t.column("type", .text)
                t.column("transfer_type", .text)
                t.column("transfer_metadata", .text)
                t.column("confidence", .double)
                t.column("raw_extraction", .text)
                t.column("created_at", .text).defaults(sql: "CURRENT_TIMESTAMP")
            }

            // calendar_events
            try db.create(table: "calendar_events") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("transaction_id", .integer).references("transactions", onDelete: .none)
                t.column("google_event_id", .text)
                t.column("title", .text)
                t.column("date", .text)
                t.column("amount", .double)
                t.column("is_synced", .integer).notNull().defaults(to: 0)
            }

            // sync_state (single-row)
            try db.create(table: "sync_state") { t in
                t.primaryKey("id", .integer, onConflict: .abort).check { $0 == 1 }
                t.column("last_sync_date", .text)
                t.column("last_history_id", .text)
                t.column("total_emails_synced", .integer).notNull().defaults(to: 0)
                t.column("total_emails_processed", .integer).notNull().defaults(to: 0)
            }

            // Indexes
            try db.create(index: "idx_emails_date", on: "emails", columns: ["date"])
            try db.create(index: "idx_emails_is_processed", on: "emails", columns: ["is_processed"])
            try db.create(index: "idx_transactions_email_id", on: "transactions", columns: ["email_id"])
            try db.create(index: "idx_transactions_category", on: "transactions", columns: ["category"])
            try db.create(index: "idx_transactions_date", on: "transactions", columns: ["transaction_date"])

            // Insert initial sync_state row
            try db.execute(sql: "INSERT INTO sync_state (id) VALUES (1)")
        }

        migrator.registerMigration("v2") { db in
            try db.alter(table: "calendar_events") { t in
                t.add(column: "currency", .text)
            }
        }

        migrator.registerMigration("v3") { db in
            // Remove duplicate transactions: same amount + currency + date, keep earliest (lowest id)
            try db.execute(sql: """
                DELETE FROM transactions WHERE id NOT IN (
                    SELECT MIN(id) FROM transactions
                    GROUP BY amount, currency, transaction_date
                )
                """)

            // Note: credit card statement emails are now routed to credit_card_bills table
            // instead of being deleted. Only auto-pay notifications are still cleaned up.
            try db.execute(sql: """
                DELETE FROM transactions
                WHERE merchant LIKE '%銀行%'
                AND (
                    description LIKE '%自動扣繳%'
                    OR description LIKE '%扣款失敗%'
                )
                """)

            // Also clean up related calendar_events for deleted transactions
            try db.execute(sql: """
                DELETE FROM calendar_events
                WHERE transaction_id NOT IN (SELECT id FROM transactions)
                """)
        }

        // MARK: - v4: Credit card bills table
        migrator.registerMigration("v4") { db in
            try db.create(table: "credit_card_bills") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("email_id", .text).references("emails", onDelete: .setNull)
                t.column("bank_name", .text).notNull()
                t.column("due_date", .text).notNull()
                t.column("amount_due", .double).notNull()
                t.column("currency", .text).notNull().defaults(to: "TWD")
                t.column("statement_period", .text)
                t.column("is_paid", .integer).notNull().defaults(to: false)
                t.column("created_at", .text).defaults(sql: "CURRENT_TIMESTAMP")
            }
            try db.create(index: "idx_credit_card_bills_due_date", on: "credit_card_bills", columns: ["due_date"])
            try db.create(index: "idx_credit_card_bills_bank_name", on: "credit_card_bills", columns: ["bank_name"])
        }
    }
}
