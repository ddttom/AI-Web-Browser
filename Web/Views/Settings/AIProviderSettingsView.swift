import SwiftUI

/// AI Provider settings view for configuring external API keys and provider selection
/// Integrates with secure keychain storage and provider management
struct AIProviderSettingsView: View {

    @StateObject private var providerManager = AIProviderManager.shared
    @State private var selectedProvider: AIProvider?
    @State private var showingAPIKeyInput = false
    @State private var showingProviderSelection = false
    @State private var pendingAPIKey = ""
    @State private var pendingProviderType: SecureKeyStorage.AIProvider?
    @State private var statusMessage = ""
    @State private var isError = false
    @State private var isValidating = false

    private let secureStorage = SecureKeyStorage.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Provider")
                        .font(.headline)
                    Text("Configure AI providers and API keys")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Divider()

            // Current Provider Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Active Provider")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    // Provider icon and info
                    HStack(spacing: 12) {
                        Image(systemName: providerIcon(for: providerManager.currentProvider))
                            .font(.title2)
                            .foregroundColor(
                                providerColor(for: providerManager.currentProvider)
                            )
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(
                                        providerColor(for: providerManager.currentProvider)
                                            .opacity(0.1))
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(providerManager.currentProvider?.displayName ?? "None")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.medium)

                            Text(providerTypeDescription(for: providerManager.currentProvider))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Switch Provider Button
                    Button("Switch") {
                        showingProviderSelection = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(providerManager.availableProviders.count <= 1)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }

            // Provider Configuration
            if let currentProvider = providerManager.currentProvider {
                providerConfigurationView(for: currentProvider)
            }

            // Available Providers
            VStack(alignment: .leading, spacing: 12) {
                Text("Available Providers")
                    .font(.subheadline)
                    .fontWeight(.medium)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2),
                    spacing: 16
                ) {
                    ForEach(SecureKeyStorage.AIProvider.allCases, id: \.self) { providerType in
                        providerCard(for: providerType)
                    }
                }
            }

            // Status Message
            if !statusMessage.isEmpty {
                HStack {
                    Image(systemName: isError ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundColor(isError ? .red : .green)
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(isError ? .red : .green)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill((isError ? Color.red : Color.green).opacity(0.1))
                )
            }

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingAPIKeyInput) {
            apiKeyInputSheet()
        }
        .sheet(isPresented: $showingProviderSelection) {
            providerSelectionSheet()
        }
        .onAppear {
            selectedProvider = providerManager.currentProvider
        }
    }

    // MARK: - Provider Configuration

    @ViewBuilder
    private func providerConfigurationView(for provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Provider Settings")
                .font(.subheadline)
                .fontWeight(.medium)

            // Model Selection
            modelSelectionView(for: provider)

            // Usage Statistics
            usageStatisticsView(for: provider)

            // Link to Usage & Billing
            Button(action: {
                NotificationCenter.default.post(name: .openUsageBilling, object: nil)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar").foregroundColor(.blue)
                    Text("Open Usage & Billing")
                }
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    @ViewBuilder
    private func modelSelectionView(for provider: AIProvider) -> some View {
        if !provider.availableModels.isEmpty {
            HStack {
                Text("Model:")
                    .font(.system(.body, design: .rounded))

                Spacer()

                modelPicker(for: provider)
            }
        }
    }

    @ViewBuilder
    private func modelPicker(for provider: AIProvider) -> some View {
        if let currentProvider = providerManager.currentProvider,
            currentProvider.providerId == provider.providerId
        {
            Picker(
                "Model",
                selection: Binding(
                    get: { currentProvider.selectedModel?.id ?? "" },
                    set: { modelId in
                        if let model = currentProvider.availableModels.first(where: {
                            $0.id == modelId
                        }) {
                            providerManager.updateSelectedModel(model)
                        }
                    }
                )
            ) {
                ForEach(currentProvider.availableModels, id: \.id) { model in
                    modelPickerItem(model)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 200)
        } else {
            Text("Provider not active")
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func modelPickerItem(_ model: AIModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.name)
                .font(.system(.body, design: .rounded))
            if let pricing = model.pricing {
                let inUSD = pricing.inputPerMTokensUSD ?? 0
                let outUSD = pricing.outputPerMTokensUSD ?? 0
                Text(String(format: "$%.2f /1M in, $%.2f /1M out", inUSD, outUSD))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let cost = model.costPerToken {
                Text("$\(String(format: "%.6f", cost))/token")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(model.capabilities, id: \.self) { cap in
                    Text(cap.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4).fill(
                                Color(NSColor.controlBackgroundColor)))
                }
                Spacer()
                Text("ctx \(model.contextWindow)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .tag(model.id)
    }

    @ViewBuilder
    private func usageStatisticsView(for provider: AIProvider) -> some View {
        let stats = provider.getUsageStatistics()
        if stats.requestCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Usage Statistics")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                statisticsHStack(stats)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
            )
        }
    }

    @ViewBuilder
    private func statisticsHStack(_ stats: AIUsageStatistics) -> some View {
        HStack {
            statItem("Requests", value: "\(stats.requestCount)")
            Spacer()
            statItem("Tokens", value: "\(stats.tokenCount)")
            Spacer()
            if let cost = stats.estimatedCost {
                statItem("Cost", value: "$\(String(format: "%.4f", cost))")
            } else {
                statItem("Cost", value: "Free")
            }
        }
    }

    @ViewBuilder
    private func statItem(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }

    // MARK: - Provider Cards

    @ViewBuilder
    private func providerCard(for providerType: SecureKeyStorage.AIProvider) -> some View {
        let hasKey = secureStorage.hasAPIKey(for: providerType)
        let isActive = providerManager.currentProvider?.providerId == providerType.rawValue

        VStack(spacing: 12) {
            // Provider Icon
            Image(systemName: providerTypeIcon(for: providerType))
                .font(.title)
                .foregroundColor(providerTypeColor(for: providerType))
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(providerTypeColor(for: providerType).opacity(0.1))
                )

            // Provider Info
            VStack(spacing: 4) {
                Text(providerType.displayName)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    // Status indicator
                    Circle()
                        .fill(hasKey ? .green : .gray)
                        .frame(width: 6, height: 6)

                    Text(hasKey ? "Configured" : "Not configured")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if isActive {
                        Text("• Active")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }

            // Action Buttons
            HStack(spacing: 8) {
                if hasKey {
                    Button("Remove") {
                        removeAPIKey(for: providerType)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.red)
                } else {
                    Button("Add Key") {
                        pendingProviderType = providerType
                        showingAPIKeyInput = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isActive ? Color.blue : Color.clear, lineWidth: 2)
                )
        )
    }

    // MARK: - Sheets

    @ViewBuilder
    private func apiKeyInputSheet() -> some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Add API Key")
                        .font(.headline)
                    if let providerType = pendingProviderType {
                        Text("Enter your \(providerType.displayName) API key")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("Cancel") {
                    showingAPIKeyInput = false
                    pendingAPIKey = ""
                    pendingProviderType = nil
                }
                .buttonStyle(.plain)
            }

            // API Key Input
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.caption)
                    .fontWeight(.medium)

                SecureField("Paste your API key here", text: $pendingAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                if let providerType = pendingProviderType {
                    Text(apiKeyHelpText(for: providerType))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Action Buttons
            HStack {
                Spacer()

                Button("Cancel") {
                    showingAPIKeyInput = false
                    pendingAPIKey = ""
                    pendingProviderType = nil
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    Task {
                        await saveAPIKey()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(pendingAPIKey.isEmpty || isValidating)
            }

            if isValidating {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Validating API key...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 400)
    }

    @ViewBuilder
    private func providerSelectionSheet() -> some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Select AI Provider")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    showingProviderSelection = false
                }
                .buttonStyle(.plain)
            }

            // Provider List
            VStack(spacing: 12) {
                ForEach(providerManager.availableProviders, id: \.providerId) { provider in
                    Button(action: {
                        Task {
                            await switchToProvider(provider)
                        }
                    }) {
                        HStack {
                            Image(systemName: providerIcon(for: provider))
                                .foregroundColor(providerColor(for: provider))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.displayName)
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.medium)

                                Text(providerTypeDescription(for: provider))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if provider.providerId == providerManager.currentProvider?.providerId {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if providerManager.isInitializing {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Switching provider...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 350)
    }

    // MARK: - Actions

    private func saveAPIKey() async {
        guard let providerType = pendingProviderType else { return }

        isValidating = true
        isError = false
        statusMessage = ""

        do {
            // Store API key
            try secureStorage.storeAPIKey(pendingAPIKey, for: providerType)

            // Add provider to available list
            providerManager.addExternalProvider(providerType)

            // Switch to new provider if it's the only external one
            if providerManager.currentProvider?.providerType == .local,
                let newProvider = providerManager.availableProviders.first(where: {
                    ($0 as? ExternalAPIProvider)?.apiProviderType == providerType
                })
            {
                try await providerManager.switchProvider(to: newProvider)
            }

            statusMessage = "\(providerType.displayName) API key saved successfully"
            isError = false

            // Close sheet
            showingAPIKeyInput = false
            pendingAPIKey = ""
            pendingProviderType = nil

        } catch {
            statusMessage = "Failed to save API key: \(error.localizedDescription)"
            isError = true
        }

        isValidating = false

        // Clear status after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            statusMessage = ""
        }
    }

    private func removeAPIKey(for providerType: SecureKeyStorage.AIProvider) {
        do {
            try secureStorage.deleteAPIKey(for: providerType)
            providerManager.removeExternalProvider(providerType)

            statusMessage = "\(providerType.displayName) API key removed"
            isError = false

        } catch {
            statusMessage = "Failed to remove API key: \(error.localizedDescription)"
            isError = true
        }

        // Clear status after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            statusMessage = ""
        }
    }

    private func switchToProvider(_ provider: AIProvider) async {
        do {
            try await providerManager.switchProvider(to: provider)
            showingProviderSelection = false

            statusMessage = "Switched to \(provider.displayName)"
            isError = false

        } catch {
            statusMessage = "Failed to switch provider: \(error.localizedDescription)"
            isError = true
        }

        // Clear status after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            statusMessage = ""
        }
    }

    // MARK: - Helper Methods

    private func providerIcon(for provider: AIProvider?) -> String {
        guard let provider = provider else { return "questionmark.circle" }

        switch provider.providerId {
        case "local_mlx":
            return "cpu"
        case "ollama":
            return "server.rack"
        case "openai":
            return "brain.head.profile"
        case "anthropic":
            return "person.crop.circle.fill"
        case "google_gemini":
            return "diamond.fill"
        default:
            return "sparkles"
        }
    }

    private func providerColor(for provider: AIProvider?) -> Color {
        guard let provider = provider else { return .gray }

        switch provider.providerId {
        case "local_mlx":
            return .blue
        case "ollama":
            return .indigo
        case "openai":
            return .green
        case "anthropic":
            return .orange
        case "google_gemini":
            return .purple
        default:
            return .gray
        }
    }

    private func providerTypeIcon(for providerType: SecureKeyStorage.AIProvider) -> String {
        switch providerType {
        case .openai:
            return "brain.head.profile"
        case .anthropic:
            return "person.crop.circle.fill"
        case .gemini:
            return "diamond.fill"
        }
    }

    private func providerTypeColor(for providerType: SecureKeyStorage.AIProvider) -> Color {
        switch providerType {
        case .openai:
            return .green
        case .anthropic:
            return .orange
        case .gemini:
            return .purple
        }
    }

    private func providerTypeDescription(for provider: AIProvider?) -> String {
        guard let provider = provider else { return "No provider selected" }

        switch provider.providerId {
        case "local_mlx":
            return "MLX framework, Apple Silicon optimized"
        case "ollama":
            return "Local Ollama service, runs any model"
        default:
            switch provider.providerType {
            case .local:
                return "Private, runs locally on your Mac"
            case .external:
                return "Cloud-based API service"
            }
        }
    }

    private func apiKeyHelpText(for providerType: SecureKeyStorage.AIProvider) -> String {
        switch providerType {
        case .openai:
            return "Get your API key from platform.openai.com/api-keys"
        case .anthropic:
            return "Get your API key from console.anthropic.com/settings/keys"
        case .gemini:
            return "Get your API key from aistudio.google.com/app/apikey"
        }
    }
}

// MARK: - Preview

#Preview {
    AIProviderSettingsView()
        .frame(width: 600, height: 700)
}
