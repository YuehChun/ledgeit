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

        // MARK: - v5: Financial analysis tables
        migrator.registerMigration("v5") { db in
            try db.create(table: "financial_reports") { t in
                t.primaryKey("id", .text)
                t.column("report_type", .text).notNull()      // monthly, quarterly, yearly
                t.column("period_start", .text).notNull()
                t.column("period_end", .text).notNull()
                t.column("summary_json", .text).notNull()
                t.column("advice_json", .text).notNull()
                t.column("goals_json", .text).notNull()
                t.column("created_at", .text).defaults(sql: "CURRENT_TIMESTAMP")
            }
            try db.create(index: "idx_financial_reports_period", on: "financial_reports", columns: ["period_start", "period_end"])

            try db.create(table: "financial_goals") { t in
                t.primaryKey("id", .text)
                t.column("type", .text).notNull()              // short_term, long_term
                t.column("title", .text).notNull()
                t.column("description", .text).notNull()
                t.column("target_amount", .double)
                t.column("target_date", .text)
                t.column("category", .text)                    // savings, budget, investment, debt
                t.column("status", .text).notNull().defaults(to: "suggested")  // suggested, accepted, completed, dismissed
                t.column("progress", .double).notNull().defaults(to: 0)
                t.column("created_at", .text).defaults(sql: "CURRENT_TIMESTAMP")
            }
            try db.create(index: "idx_financial_goals_status", on: "financial_goals", columns: ["status"])
            try db.create(index: "idx_financial_goals_type", on: "financial_goals", columns: ["type"])
        }

        // MARK: - v6: Prompt version control
        migrator.registerMigration("v6") { db in
            try db.create(table: "prompt_versions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("base_persona_id", .text).notNull()
                t.column("spending_philosophy", .text).notNull()
                t.column("savings_target", .double).notNull()
                t.column("risk_level", .text).notNull()
                t.column("category_budget_hints", .text).notNull()
                t.column("user_feedback", .text)
                t.column("is_active", .integer).notNull().defaults(to: false)
                t.column("created_at", .text).defaults(sql: "CURRENT_TIMESTAMP")
            }
            try db.create(index: "idx_prompt_versions_active", on: "prompt_versions", columns: ["is_active"])
        }

        // MARK: - v7: Transaction review support
        migrator.registerMigration("v7") { db in
            try db.alter(table: "transactions") { t in
                t.add(column: "is_reviewed", .integer).notNull().defaults(to: false)
            }
            try db.create(index: "idx_transactions_is_reviewed", on: "transactions", columns: ["is_reviewed"])
        }

        // MARK: - v8: Soft delete support
        migrator.registerMigration("v8") { db in
            try db.alter(table: "transactions") { t in
                t.add(column: "deleted_at", .text)
            }
            try db.create(index: "idx_transactions_deleted_at", on: "transactions", columns: ["deleted_at"])
        }
    }
}
