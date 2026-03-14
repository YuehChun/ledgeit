import Foundation

actor CalendarService {
    private let baseURL = "https://www.googleapis.com/calendar/v3"
    private let accessTokenProvider: @Sendable () async throws -> String

    init(accessTokenProvider: @escaping @Sendable () async throws -> String) {
        self.accessTokenProvider = accessTokenProvider
    }

    struct CalendarEventRequest: Codable, Sendable {
        let summary: String
        let description: String?
        let start: EventDateTime
        let end: EventDateTime
        let reminders: Reminders?
    }

    struct EventDateTime: Codable, Sendable {
        let date: String?
        let dateTime: String?
        let timeZone: String?
    }

    struct Reminders: Codable, Sendable {
        let useDefault: Bool
        let overrides: [ReminderOverride]?
    }

    struct ReminderOverride: Codable, Sendable {
        let method: String
        let minutes: Int
    }

    struct CalendarEventResponse: Codable, Sendable {
        let id: String
        let summary: String?
        let htmlLink: String?
    }

    func createPaymentEvent(
        merchant: String,
        amount: Double,
        currency: String,
        date: String,
        description: String? = nil
    ) async throws -> CalendarEventResponse {
        guard await LicenseManager.shared.isPro else { throw CalendarError.unauthorized }
        let token = try await accessTokenProvider()
        let url = URL(string: "\(baseURL)/calendars/primary/events")!

        let event = CalendarEventRequest(
            summary: "\(merchant) - \(currency) \(String(format: "%.2f", amount))",
            description: description ?? "Payment due: \(merchant)",
            start: EventDateTime(date: date, dateTime: nil, timeZone: nil),
            end: EventDateTime(date: date, dateTime: nil, timeZone: nil),
            reminders: Reminders(
                useDefault: false,
                overrides: [
                    ReminderOverride(method: "popup", minutes: 1440) // 1 day before
                ]
            )
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(event)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CalendarError.requestFailed(0)
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw CalendarError.requestFailed(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(CalendarEventResponse.self, from: data)
    }

    func deleteEvent(eventId: String) async throws {
        let token = try await accessTokenProvider()
        let url = URL(string: "\(baseURL)/calendars/primary/events/\(eventId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CalendarError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }
}

enum CalendarError: LocalizedError {
    case requestFailed(Int)
    case unauthorized
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .requestFailed(let code): return "Calendar API request failed with status \(code)"
        case .unauthorized: return "Calendar access unauthorized"
        case .invalidResponse: return "Invalid response from Calendar API"
        }
    }
}
