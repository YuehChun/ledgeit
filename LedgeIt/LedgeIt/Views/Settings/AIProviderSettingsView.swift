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
    @State private var providersExpanded = false
    @State private var modelsExpanded = true
    @State private var customModelText: [String: String] = [:]
    @State private var useCustomModel: Set<String> = []

    init() {
        _config = State(initialValue: AIProviderConfigStore.load())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(isExpanded: $providersExpanded) {
                providerManagementContent
            } label: {
                Label("AI Providers", systemImage: "brain.head.profile")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.purple)
            }
            .padding(14)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            DisclosureGroup(isExpanded: $modelsExpanded) {
                modelAssignmentContent
            } label: {
                Label("Model Assignment", systemImage: "cpu")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }
            .padding(14)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .onAppear(perform: loadState)
        .sheet(isPresented: $showAddEndpointSheet) {
            EndpointEditorSheet(
                endpoint: nil,
                onSave: { newEndpoint, apiKey in
                    config.endpoints.append(newEndpoint)
                    if let apiKey, !apiKey.isEmpty {
                        do {
                            try KeychainService.saveEndpointAPIKey(endpointId: newEndpoint.id, value: apiKey)
                            endpointAPIKeys[newEndpoint.id] = apiKey
                        } catch {
                            saveMessage = "Failed to save API key"
                        }
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
                            do {
                                try KeychainService.saveEndpointAPIKey(endpointId: updatedEndpoint.id, value: apiKey)
                                endpointAPIKeys[updatedEndpoint.id] = apiKey
                            } catch {
                                saveMessage = "Failed to save API key"
                            }
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

    // MARK: - Provider Management Content

    private var providerManagementContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OpenAI Compatible Endpoints")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)
                .padding(.top, 8)

            ForEach(config.endpoints) { endpoint in
                endpointRow(for: endpoint)
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

            if let saveMessage {
                Text(saveMessage)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Compact Endpoint Row

    private func endpointRow(for endpoint: OpenAICompatibleEndpoint) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(endpoint.name)
                        .font(.callout)
                        .fontWeight(.medium)
                    endpointStatusBadge(for: endpoint)
                }
                Text(endpoint.baseURL)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Edit") { editingEndpoint = endpoint }
                .buttonStyle(.bordered)
                .controlSize(.mini)

            Button("Delete", role: .destructive) { endpointToDelete = endpoint }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(config.endpoints.count <= 1)
        }
        .padding(8)
        .background(.background.tertiary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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

        return HStack(spacing: 3) {
            Circle().fill(status.1).frame(width: 5, height: 5)
            Text(status.0).font(.caption2).foregroundStyle(status.1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
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
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)
                .frame(width: 130, alignment: .trailing)
            SecureField(placeholder, text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
            Button("Save") {
                let value = binding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if value.isEmpty {
                    KeychainService.delete(key: key)
                    flashSaveMessage("Saved")
                } else {
                    do {
                        try KeychainService.save(key: key, value: value)
                        flashSaveMessage("Saved")
                    } catch {
                        flashSaveMessage("Failed to save key")
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Model Assignment Content

    private var modelAssignmentContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer().frame(height: 4)

            modelAssignmentRow(label: "Classification", description: "email filtering", keyPath: \.classification)
            modelAssignmentRow(label: "Extraction", description: "transaction parsing", keyPath: \.extraction)
            modelAssignmentRow(label: "Statement", description: "PDF analysis", keyPath: \.statement)
            modelAssignmentRow(label: "Chat", description: "AI assistant", keyPath: \.chat)
            modelAssignmentRow(label: "Advisor", description: "financial analysis & goals", keyPath: \.advisor)

            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    config = .default
                    useCustomModel.removeAll()
                    customModelText.removeAll()
                    saveConfig()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func modelAssignmentRow(
        label: String,
        description: String,
        keyPath: WritableKeyPath<AIProviderConfiguration, ModelAssignment>
    ) -> some View {
        let assignment = config[keyPath: keyPath]
        let groups = modelGroups(for: assignment)
        let allModels = ModelCatalog.allModels(for: groups)
        let isCustom = useCustomModel.contains(label) || groups.isEmpty
        let currentInList = allModels.contains { $0.id == assignment.model }

        return HStack(spacing: 10) {
            // Label
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.callout)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 100, alignment: .leading)

            // Provider picker
            Picker("", selection: Binding(
                get: { providerPickerValue(for: assignment) },
                set: { newValue in
                    applyProviderSelection(newValue, to: keyPath)
                    // Reset custom state and auto-select first model for new provider
                    useCustomModel.remove(label)
                    let newAssignment = config[keyPath: keyPath]
                    let newGroups = modelGroups(for: newAssignment)
                    let newModels = ModelCatalog.allModels(for: newGroups)
                    if !newModels.contains(where: { $0.id == newAssignment.model }),
                       let first = newModels.first {
                        config[keyPath: keyPath].model = first.id
                        saveConfig()
                    }
                }
            )) {
                ForEach(availableProviderOptions, id: \.id) { option in
                    Text(option.label).tag(option.id)
                }
            }
            .labelsHidden()
            .frame(width: 130)

            // Model picker or custom text field
            if isCustom || (!currentInList && !groups.isEmpty) {
                // Custom input mode
                HStack(spacing: 4) {
                    TextField("model-id", text: Binding(
                        get: { config[keyPath: keyPath].model },
                        set: { newModel in
                            config[keyPath: keyPath].model = newModel
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .onSubmit { saveConfig() }

                    if !groups.isEmpty {
                        Button {
                            useCustomModel.remove(label)
                            if let first = allModels.first {
                                config[keyPath: keyPath].model = first.id
                                saveConfig()
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("Switch to model list")
                    }
                }
            } else {
                // Grouped picker mode
                HStack(spacing: 4) {
                    Picker("", selection: Binding(
                        get: { config[keyPath: keyPath].model },
                        set: { newModel in
                            if newModel == "__custom__" {
                                useCustomModel.insert(label)
                                customModelText[label] = config[keyPath: keyPath].model
                            } else {
                                config[keyPath: keyPath].model = newModel
                                saveConfig()
                            }
                        }
                    )) {
                        ForEach(groups) { group in
                            Section(header: Text(group.label)) {
                                ForEach(group.models) { model in
                                    Text(model.label).tag(model.id)
                                }
                            }
                        }
                        Divider()
                        Text("Custom...").tag("__custom__")
                    }
                    .labelsHidden()
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(.background.tertiary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Model Group Resolution

    private func modelGroups(for assignment: ModelAssignment) -> [ModelCatalog.ModelGroup] {
        let endpointName: String?
        if assignment.provider == .openAICompatible, let eid = assignment.endpointId {
            endpointName = config.endpoints.first(where: { $0.id == eid })?.name
        } else {
            endpointName = nil
        }
        return ModelCatalog.groups(for: assignment.provider, endpointName: endpointName)
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

        for endpoint in config.endpoints {
            options.append(ProviderOption(
                id: "endpoint_\(endpoint.id.uuidString)",
                label: endpoint.name,
                provider: .openAICompatible,
                endpointId: endpoint.id
            ))
        }

        let hasAnthropicKey = !anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasAnthropicKey {
            options.append(ProviderOption(id: "anthropic", label: "Anthropic", provider: .anthropic, endpointId: nil))
        }

        let hasGoogleAIKey = !googleAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasGoogleAIKey {
            options.append(ProviderOption(id: "google", label: "Google AI", provider: .google, endpointId: nil))
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

        let useCases: [WritableKeyPath<AIProviderConfiguration, ModelAssignment>] =
            [\.classification, \.extraction, \.statement, \.chat, \.advisor]
        for kp in useCases {
            if config[keyPath: kp].endpointId == endpoint.id {
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

    private func loadState() {
        anthropicAPIKey = KeychainService.load(key: .anthropicAPIKey) ?? ""
        googleAIAPIKey = KeychainService.load(key: .googleAIAPIKey) ?? ""
        for endpoint in config.endpoints {
            if let key = KeychainService.loadEndpointAPIKey(endpointId: endpoint.id) {
                endpointAPIKeys[endpoint.id] = key
            }
        }

        // Detect which assignments have custom (non-catalog) models
        let useCases: [(String, KeyPath<AIProviderConfiguration, ModelAssignment>)] = [
            ("Classification", \.classification),
            ("Extraction", \.extraction),
            ("Statement", \.statement),
            ("Chat", \.chat),
            ("Advisor", \.advisor),
        ]
        for (label, kp) in useCases {
            let assignment = config[keyPath: kp]
            let groups = modelGroups(for: assignment)
            let allModels = ModelCatalog.allModels(for: groups)
            if !groups.isEmpty && !allModels.contains(where: { $0.id == assignment.model }) {
                useCustomModel.insert(label)
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
