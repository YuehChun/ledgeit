import SwiftUI

struct FormCardView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 16) {
            cardContent
        }
        .padding(24)
        .frame(maxWidth: 400)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThickMaterial)
        )
        .shadow(radius: 20)
    }

    @ViewBuilder
    private var cardContent: some View {
        switch viewModel.currentStep {
        case .welcome:
            welcomeCard
        case .apiKey:
            apiKeyCard
        case .gmailAuth:
            gmailAuthCard
        case .emailReview:
            emailReviewCard
        case .pdfPassword:
            pdfPasswordCard
        case .suggestions:
            suggestionsCard
        default:
            EmptyView()
        }
    }

    // MARK: - Welcome / Language Picker

    private var welcomeCard: some View {
        VStack(spacing: 16) {
            Text("Select Language / \u{9078}\u{64C7}\u{8A9E}\u{8A00}")
                .font(.headline)

            HStack(spacing: 12) {
                Button("English") {
                    Task { await viewModel.selectLanguage("en") }
                }
                .buttonStyle(.borderedProminent)

                Button("\u{7E41}\u{9AD4}\u{4E2D}\u{6587}") {
                    Task { await viewModel.selectLanguage("zh-Hant") }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - API Key Setup

    private var apiKeyCard: some View {
        VStack(spacing: 12) {
            Text(localizedTitle("AI Service Setup", zh: "AI \u{670D}\u{52D9}\u{8A2D}\u{5B9A}"))
                .font(.headline)

            Picker(localizedTitle("Provider", zh: "\u{4F9B}\u{61C9}\u{5546}"), selection: $viewModel.apiKeyEndpointName) {
                Text("OpenRouter").tag("OpenRouter")
                Text("OpenAI").tag("OpenAI")
                Text("Custom").tag("Custom")
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.apiKeyEndpointName) { _, newValue in
                switch newValue {
                case "OpenRouter":
                    viewModel.apiKeyEndpointURL = "https://openrouter.ai/api/v1"
                case "OpenAI":
                    viewModel.apiKeyEndpointURL = "https://api.openai.com/v1"
                default:
                    break
                }
            }

            if viewModel.apiKeyEndpointName == "Custom" {
                TextField("Endpoint URL", text: $viewModel.apiKeyEndpointURL)
                    .textFieldStyle(.roundedBorder)
            }

            SecureField("API Key", text: $viewModel.apiKeyValue)
                .textFieldStyle(.roundedBorder)

            if let error = viewModel.formError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button(localizedTitle("Connect", zh: "\u{9023}\u{63A5}")) {
                Task { await viewModel.submitAPIKey() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.apiKeyValue.isEmpty)
        }
    }

    // MARK: - Gmail Credentials

    private var gmailAuthCard: some View {
        VStack(spacing: 12) {
            Text(localizedTitle("Gmail Authentication", zh: "Gmail \u{8A8D}\u{8B49}"))
                .font(.headline)

            TextField("Client ID", text: $viewModel.googleClientID)
                .textFieldStyle(.roundedBorder)

            SecureField("Client Secret", text: $viewModel.googleClientSecret)
                .textFieldStyle(.roundedBorder)

            if let error = viewModel.formError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button(localizedTitle("Authenticate", zh: "\u{9A57}\u{8B49}")) {
                Task { await viewModel.submitGmailCredentials() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.googleClientID.isEmpty || viewModel.googleClientSecret.isEmpty)
        }
    }

    // MARK: - Email Review

    private var emailReviewCard: some View {
        VStack(spacing: 12) {
            Text(localizedTitle("Transaction Review", zh: "\u{4EA4}\u{6613}\u{78BA}\u{8A8D}"))
                .font(.headline)

            Text(localizedTitle(
                "\(viewModel.extractedTransactionCount) transactions extracted",
                zh: "\u{5DF2}\u{63D0}\u{53D6} \(viewModel.extractedTransactionCount) \u{7B46}\u{4EA4}\u{6613}"
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Button(localizedTitle("Confirm", zh: "\u{78BA}\u{8A8D}")) {
                Task { await viewModel.confirmEmailReview() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - PDF Password

    private var pdfPasswordCard: some View {
        VStack(spacing: 12) {
            Text(localizedTitle("PDF Password", zh: "PDF \u{5BC6}\u{78BC}"))
                .font(.headline)

            TextField(localizedTitle("Bank Name", zh: "\u{9280}\u{884C}\u{540D}\u{7A31}"), text: $viewModel.pdfBankName)
                .textFieldStyle(.roundedBorder)

            TextField(localizedTitle("Card Label (optional)", zh: "\u{5361}\u{7247}\u{6A19}\u{7C64}\u{FF08}\u{53EF}\u{9078}\u{FF09}"), text: $viewModel.pdfCardLabel)
                .textFieldStyle(.roundedBorder)

            SecureField(localizedTitle("Password", zh: "\u{5BC6}\u{78BC}"), text: $viewModel.pdfPassword)
                .textFieldStyle(.roundedBorder)

            if let error = viewModel.formError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack(spacing: 12) {
                Button(localizedTitle("Skip", zh: "\u{8DF3}\u{904E}")) {
                    Task { await viewModel.skipPDFPassword() }
                }
                .buttonStyle(.bordered)

                Button(localizedTitle("Submit", zh: "\u{63D0}\u{4EA4}")) {
                    Task { await viewModel.submitPDFPassword() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.pdfBankName.isEmpty || viewModel.pdfPassword.isEmpty)
            }
        }
    }

    // MARK: - Suggestions

    private var suggestionsCard: some View {
        VStack(spacing: 12) {
            Text(localizedTitle("Financial Suggestions", zh: "\u{8CA1}\u{52D9}\u{5EFA}\u{8B70}"))
                .font(.headline)

            Button(localizedTitle("Yes, generate suggestions", zh: "\u{662F}\u{7684}\u{FF0C}\u{751F}\u{6210}\u{5EFA}\u{8B70}")) {
                Task { await viewModel.confirmSuggestions() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Helpers

    private func localizedTitle(_ en: String, zh: String) -> String {
        viewModel.selectedLanguage == "zh-Hant" ? zh : en
    }
}
