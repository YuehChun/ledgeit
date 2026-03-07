import SwiftUI

// MARK: - Main View

struct AIProviderSettingsView: View {
    @State private var config: AIProviderConfiguration
    @State private var showAddEndpointSheet = false
    @State private var editingEndpoint: OpenAICompatibleEndpoint?
    @State private var anthropicAPIKey: String = ""
    @State private var googleAIAPIKey: String = ""
    @State private var endpointAPIKeys: [UUID: String] = [:]
    @State private var saveMessage: String?
    @State private var endpointToDelete: OpenAICompatibleEndpoint?

    init() {
        _config = State(initialValue: AIProviderConfigStore.load())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            providerManagementSection
            modelAssignmentSection
        }
    }

    // MARK: - Section 1: Provider Management

    private var providerManagementSection: some View {
        SettingsSection(title: "AI Providers", icon: "brain.head.profile", color: .purple) {
            VStack(alignment: .leading, spacing: 14) {
                // OpenAI Compatible Endpoints
                Text("OpenAI Compatible Endpoints")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)

                ForEach(config.endpoints) { endpoint in
                    endpointCard(for: endpoint)
                }

                Button {
                    showAddEndpointSheet = true
                } label: {
                    Label("Add Endpoint", systemImage: "plus.circle")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Divider()

                // Direct Providers
                Text("Direct Providers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)

                directProviderField(
                    label: "Anthropic API Key",
                    placeholder: "sk-ant-...",
                    key: .anthropicAPIKey,
                    binding: $anthropicAPIKey
                )

                directProviderField(
                    label: "Google AI API Key",
                    placeholder: "AIza...",
                    key: .googleAIAPIKey,
                    binding: $googleAIAPIKey
                )
            }
        }
        .onAppear(perform: loadDirectProviderKeys)
        .sheet(isPresented: $showAddEndpointSheet) {
            EndpointEditorSheet(
                endpoint: nil,
                onSave: { newEndpoint, apiKey in
                    config.endpoints.append(newEndpoint)
                    if let apiKey, !apiKey.isEmpty {
                        try? KeychainService.saveEndpointAPIKey(endpointId: newEndpoint.id, value: apiKey)
                        endpointAPIKeys[newEndpoint.id] = apiKey
                    }
                    saveConfig()
                }
            )
        }
        .sheet(item: $editingEndpoint) { endpoint in
            EndpointEditorSheet(
                endpoint: endpoint,
                onSave: { updatedEndpoint, apiKey in
                    if let idx = config.endpoints.firstIndex(where: { $0.id == updatedEndpoint.id }) {
                        config.endpoints[idx] = updatedEndpoint
                    }
                    if let apiKey {
                        if apiKey.isEmpty {
                            KeychainService.deleteEndpointAPIKey(endpointId: updatedEndpoint.id)
                            endpointAPIKeys.removeValue(forKey: updatedEndpoint.id)
                        } else {
                            try? KeychainService.saveEndpointAPIKey(endpointId: updatedEndpoint.id, value: apiKey)
                            endpointAPIKeys[updatedEndpoint.id] = apiKey
                        }
                    }
                    saveConfig()
                }
            )
        }
        .confirmationDialog(
            "Delete endpoint?",
            isPresented: Binding(
                get: { endpointToDelete != nil },
                set: { if !$0 { endpointToDelete = nil } }
            ),
            presenting: endpointToDelete
        ) { endpoint in
            Button("Delete \(endpoint.name)", role: .destructive) {
                deleteEndpoint(endpoint)
                endpointToDelete = nil
            }
        } message: { endpoint in
            Text("This will remove \"\(endpoint.name)\" and reset any model assignments using it.")
        }
    }

    // MARK: - Endpoint Card

    private func endpointCard(for endpoint: OpenAICompatibleEndpoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(endpoint.name)
                    .font(.callout)
                    .fontWeight(.medium)
                Spacer()
                endpointStatusBadge(for: endpoint)
            }

            Text(endpoint.baseURL)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            if !endpoint.defaultModel.isEmpty {
                HStack(spacing: 4) {
                    Text("Model:")
                        .foregroundStyle(.secondary)
                    Text(endpoint.defaultModel)
                }
                .font(.caption)
            }

            HStack(spacing: 8) {
                Button("Edit") {
                    editingEndpoint = endpoint
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("Delete", role: .destructive) {
                    endpointToDelete = endpoint
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(config.endpoints.count <= 1)
            }
            .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.tertiary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func endpointStatusBadge(for endpoint: OpenAICompatibleEndpoint) -> some View {
        let hasKey = endpointAPIKeys[endpoint.id].map { !$0.isEmpty } ?? false
        let status: (String, Color)
        if !endpoint.requiresAPIKey {
            status = ("no key needed", .green)
        } else if hasKey {
            status = ("configured", .green)
        } else {
            status = ("no API key", .orange)
        }

        return HStack(spacing: 4) {
            Circle()
                .fill(status.1)
                .frame(width: 6, height: 6)
            Text(status.0)
                .font(.caption2)
                .foregroundStyle(status.1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(status.1.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Direct Provider Fields

    private func directProviderField(
        label: String,
        placeholder: String,
        key: KeychainService.Key,
        binding: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)
            HStack(spacing: 8) {
                SecureField(placeholder, text: binding)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                Button("Save") {
                    let value = binding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if value.isEmpty {
                        KeychainService.delete(key: key)
                    } else {
                        try? KeychainService.save(key: key, value: value)
                    }
                    flashSaveMessage("Saved")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Section 2: Model Assignment

    private var modelAssignmentSection: some View {
        SettingsSection(title: "Model Assignment", icon: "cpu", color: .blue) {
            VStack(alignment: .leading, spacing: 14) {
                modelAssignmentRow(
                    label: "Classification",
                    description: "email filtering",
                    keyPath: \.classification
                )
                modelAssignmentRow(
                    label: "Extraction",
                    description: "transaction parsing",
                    keyPath: \.extraction
                )
                modelAssignmentRow(
                    label: "Statement",
                    description: "PDF analysis",
                    keyPath: \.statement
                )
                modelAssignmentRow(
                    label: "Chat",
                    description: "AI assistant",
                    keyPath: \.chat
                )

                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        config = .default
                        saveConfig()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let saveMessage {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }
        }
    }

    private func modelAssignmentRow(
        label: String,
        description: String,
        keyPath: WritableKeyPath<AIProviderConfiguration, ModelAssignment>
    ) -> some View {
        let assignment = config[keyPath: keyPath]

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.callout)
                    .fontWeight(.medium)
                Text("(\(description))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Provider")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Picker("Provider", selection: Binding(
                        get: { providerPickerValue(for: assignment) },
                        set: { newValue in
                            applyProviderSelection(newValue, to: keyPath)
                        }
                    )) {
                        ForEach(availableProviderOptions, id: \.id) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Model")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("model-id", text: Binding(
                        get: { config[keyPath: keyPath].model },
                        set: { newModel in
                            config[keyPath: keyPath].model = newModel
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .onSubmit { saveConfig() }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.tertiary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Provider Picker Helpers

    private struct ProviderOption: Identifiable {
        let id: String
        let label: String
        let provider: AIProvider
        let endpointId: UUID?
    }

    private var availableProviderOptions: [ProviderOption] {
        var options: [ProviderOption] = []

        // Add each OpenAI Compatible endpoint
        for endpoint in config.endpoints {
            options.append(ProviderOption(
                id: "endpoint_\(endpoint.id.uuidString)",
                label: endpoint.name,
                provider: .openAICompatible,
                endpointId: endpoint.id
            ))
        }

        // Add Anthropic if key is configured
        let hasAnthropicKey = !anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasAnthropicKey {
            options.append(ProviderOption(
                id: "anthropic",
                label: "Anthropic",
                provider: .anthropic,
                endpointId: nil
            ))
        }

        // Add Google AI if key is configured
        let hasGoogleAIKey = !googleAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasGoogleAIKey {
            options.append(ProviderOption(
                id: "google",
                label: "Google AI",
                provider: .google,
                endpointId: nil
            ))
        }

        return options
    }

    private func providerPickerValue(for assignment: ModelAssignment) -> String {
        switch assignment.provider {
        case .openAICompatible:
            if let eid = assignment.endpointId {
                return "endpoint_\(eid.uuidString)"
            }
            return ""
        case .anthropic:
            return "anthropic"
        case .google:
            return "google"
        }
    }

    private func applyProviderSelection(
        _ value: String,
        to keyPath: WritableKeyPath<AIProviderConfiguration, ModelAssignment>
    ) {
        if value == "anthropic" {
            config[keyPath: keyPath].provider = .anthropic
            config[keyPath: keyPath].endpointId = nil
        } else if value == "google" {
            config[keyPath: keyPath].provider = .google
            config[keyPath: keyPath].endpointId = nil
        } else if value.hasPrefix("endpoint_") {
            let uuidString = String(value.dropFirst("endpoint_".count))
            config[keyPath: keyPath].provider = .openAICompatible
            config[keyPath: keyPath].endpointId = UUID(uuidString: uuidString)
        }
        saveConfig()
    }

    // MARK: - Actions

    private func deleteEndpoint(_ endpoint: OpenAICompatibleEndpoint) {
        guard config.endpoints.count > 1 else { return }
        config.endpoints.removeAll { $0.id == endpoint.id }
        KeychainService.deleteEndpointAPIKey(endpointId: endpoint.id)
        endpointAPIKeys.removeValue(forKey: endpoint.id)

        // Reset any assignments pointing to this endpoint
        let useCases: [WritableKeyPath<AIProviderConfiguration, ModelAssignment>] =
            [\.classification, \.extraction, \.statement, \.chat]
        for kp in useCases {
            if config[keyPath: kp].endpointId == endpoint.id {
                // Fall back to first available endpoint or default
                if let fallback = config.endpoints.first {
                    config[keyPath: kp].endpointId = fallback.id
                }
            }
        }
        saveConfig()
    }

    private func saveConfig() {
        AIProviderConfigStore.save(config)
    }

    private func loadDirectProviderKeys() {
        anthropicAPIKey = KeychainService.load(key: .anthropicAPIKey) ?? ""
        googleAIAPIKey = KeychainService.load(key: .googleAIAPIKey) ?? ""

        // Load endpoint API keys for status display
        for endpoint in config.endpoints {
            if let key = KeychainService.loadEndpointAPIKey(endpointId: endpoint.id) {
                endpointAPIKeys[endpoint.id] = key
            }
        }
    }

    private func flashSaveMessage(_ message: String) {
        withAnimation { saveMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { saveMessage = nil }
        }
    }
}

// MARK: - Endpoint Editor Sheet

struct EndpointEditorSheet: View {
    let endpoint: OpenAICompatibleEndpoint?
    let onSave: (OpenAICompatibleEndpoint, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var requiresAPIKey: Bool = true
    @State private var defaultModel: String = ""
    @State private var validationError: String?

    var isEditing: Bool { endpoint != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "Edit Endpoint" : "Add Endpoint")
                .font(.title3)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 12) {
                fieldRow(label: "Name") {
                    TextField("e.g. OpenRouter", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                fieldRow(label: "Base URL") {
                    TextField("https://api.example.com/v1", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("Requires API Key", isOn: $requiresAPIKey)
                    .font(.callout)

                if requiresAPIKey {
                    fieldRow(label: "API Key") {
                        SecureField(isEditing ? "Leave empty to keep current" : "sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                fieldRow(label: "Default Model") {
                    TextField("model-id", text: $defaultModel)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(isEditing ? "Update" : "Add") {
                    guard validate() else { return }
                    let result = OpenAICompatibleEndpoint(
                        id: endpoint?.id ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                        requiresAPIKey: requiresAPIKey,
                        defaultModel: defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    let keyToSave: String? = requiresAPIKey
                        ? (apiKey.isEmpty && isEditing ? nil : apiKey)
                        : ""
                    onSave(result, keyToSave)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            if let ep = endpoint {
                name = ep.name
                baseURL = ep.baseURL
                requiresAPIKey = ep.requiresAPIKey
                defaultModel = ep.defaultModel
                if ep.requiresAPIKey {
                    apiKey = KeychainService.loadEndpointAPIKey(endpointId: ep.id) ?? ""
                }
            }
        }
    }

    @ViewBuilder
    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)
            content()
        }
    }

    private func validate() -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            validationError = "Name is required."
            return false
        }
        if trimmedURL.isEmpty {
            validationError = "Base URL is required."
            return false
        }
        guard URL(string: trimmedURL) != nil else {
            validationError = "Base URL is not a valid URL."
            return false
        }
        validationError = nil
        return true
    }
}
