import Foundation

/// Local MLX provider implementing the AIProvider protocol
/// Wraps existing GemmaService to provide unified interface
@MainActor
class LocalMLXProvider: AIProvider, ObservableObject {

    // MARK: - AIProvider Implementation

    let providerId = "local_mlx"
    let displayName = "Local MLX (Private)"
    let providerType = AIProviderType.local

    @Published var isInitialized: Bool = false

    @Published var availableModels: [AIModel] = []

    // Fallback models if no local models are discovered
    private let fallbackModels: [AIModel] = [
        AIModel(
            id: "gemma-3-2b",
            name: "Gemma 3 2B (4-bit)",
            description: "Default model - will be downloaded from Hugging Face",
            contextWindow: 8192,
            costPerToken: nil,
            pricing: nil,
            capabilities: [.textGeneration, .conversation, .summarization],
            provider: "local_mlx",
            isAvailable: true
        )
    ]

    var selectedModel: AIModel? {
        didSet {
            if let model = selectedModel {
                UserDefaults.standard.set(model.id, forKey: "localMLXSelectedModel")
            }
        }
    }

    // MARK: - Private Properties

    private let gemmaService: GemmaService
    private let aiConfiguration: AIConfiguration
    private let mlxWrapper: MLXWrapper
    private let mlxModelService: MLXModelService
    private let privacyManager: PrivacyManager
    private let modelDiscovery = ModelDiscoveryService.shared

    private var usageStats = AIUsageStatistics(
        requestCount: 0,
        tokenCount: 0,
        averageResponseTime: 0,
        errorCount: 0,
        lastUsed: nil,
        estimatedCost: nil
    )

    // MARK: - Initialization

    init() {
        // Initialize dependencies (reuse existing services)
        self.mlxWrapper = MLXWrapper()
        self.privacyManager = PrivacyManager()
        self.mlxModelService = MLXModelService.shared

        // Get optimal configuration for current hardware
        self.aiConfiguration = HardwareDetector.getOptimalAIConfiguration()

        // Initialize Gemma service
        self.gemmaService = GemmaService(
            configuration: aiConfiguration,
            mlxWrapper: mlxWrapper,
            privacyManager: privacyManager,
            mlxModelService: mlxModelService
        )

        // Initialize available models from discovery service
        Task {
            await loadAvailableModels()
        }

        AppLog.debug("Local MLX Provider init: framework=\(aiConfiguration.framework)")
    }

    // MARK: - Lifecycle Methods

    func initialize() async throws {
        do {
            // Validate hardware requirements
            try validateHardware()

            // Initialize underlying services
            try await mlxWrapper.initialize()
            try await privacyManager.initialize()
            try await gemmaService.initialize()

            isInitialized = true
            AppLog.debug("Local MLX Provider initialized")

        } catch {
            isInitialized = false
            throw AIProviderError.invalidConfiguration(
                "MLX initialization failed: \(error.localizedDescription)")
        }
    }

    func isReady() async -> Bool {
        guard isInitialized else { return false }
        return await mlxModelService.isAIReady()
    }

    func cleanup() async {
        isInitialized = false
        // MLX resources are managed by shared services, don't clean up here
        AppLog.debug("Local MLX Provider cleaned up")
    }

    // MARK: - Core AI Methods

    func generateResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage],
        model: AIModel?
    ) async throws -> AIResponse {
        let startTime = Date()

        do {
            let response = try await gemmaService.generateResponse(
                query: query,
                context: context,
                conversationHistory: conversationHistory
            )

            let responseTime = Date().timeIntervalSince(startTime)
            let tokenCount = Int(Double(response.text.count) / 3.5)  // Rough estimation

            updateUsageStats(
                tokenCount: tokenCount,
                responseTime: responseTime,
                error: false
            )
            // Persist usage event for analytics (no cost for local)
            AIUsageStore.shared.append(
                providerId: providerId,
                modelId: (model?.id ?? selectedModel?.id ?? AIModel.defaultLocal.id),
                promptTokens: 0,
                completionTokens: tokenCount,
                estimatedCostUSD: nil,
                success: true,
                latencyMs: Int(responseTime * 1000),
                contextIncluded: (context != nil)
            )

            return response

        } catch {
            let responseTime = Date().timeIntervalSince(startTime)
            updateUsageStats(tokenCount: 0, responseTime: responseTime, error: true)
            throw error
        }
    }

    func generateStreamingResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage],
        model: AIModel?
    ) async throws -> AsyncThrowingStream<String, Error> {
        let modelId = (model?.id ?? selectedModel?.id ?? AIModel.defaultLocal.id)
        let startTime = Date()
        let inner = try await gemmaService.generateStreamingResponse(
            query: query,
            context: context,
            conversationHistory: conversationHistory
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var charCount = 0
                    for try await chunk in inner {
                        charCount += chunk.count
                        continuation.yield(chunk)
                    }
                    let tokenCount = Int(Double(charCount) / 3.5)
                    let responseTime = Date().timeIntervalSince(startTime)
                    AIUsageStore.shared.append(
                        providerId: providerId,
                        modelId: modelId,
                        promptTokens: 0,
                        completionTokens: tokenCount,
                        estimatedCostUSD: nil,
                        success: true,
                        latencyMs: Int(responseTime * 1000),
                        contextIncluded: (context != nil)
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func generateRawResponse(
        prompt: String,
        model: AIModel?
    ) async throws -> String {
        let startTime = Date()

        do {
            let response = try await gemmaService.generateRawResponse(prompt: prompt)

            let responseTime = Date().timeIntervalSince(startTime)
            let tokenCount = Int(Double(response.count) / 3.5)  // Rough estimation

            updateUsageStats(
                tokenCount: tokenCount,
                responseTime: responseTime,
                error: false
            )
            AIUsageStore.shared.append(
                providerId: providerId,
                modelId: (model?.id ?? selectedModel?.id ?? AIModel.defaultLocal.id),
                promptTokens: 0,
                completionTokens: tokenCount,
                estimatedCostUSD: nil,
                success: true,
                latencyMs: Int(responseTime * 1000),
                contextIncluded: false
            )

            return response

        } catch {
            let responseTime = Date().timeIntervalSince(startTime)
            updateUsageStats(tokenCount: 0, responseTime: responseTime, error: true)
            throw error
        }
    }

    func summarizeConversation(
        _ messages: [ConversationMessage],
        model: AIModel?
    ) async throws -> String {
        return try await gemmaService.summarizeConversation(messages)
    }

    // MARK: - Configuration Methods

    func validateConfiguration() async throws {
        // Validate hardware compatibility
        try validateHardware()

        // Check if model is available
        guard await mlxModelService.isAIReady() else {
            throw AIProviderError.modelNotAvailable("Gemma model not downloaded or corrupted")
        }
    }

    func getConfigurableSettings() -> [AIProviderSetting] {
        return [
            AIProviderSetting(
                id: "model_selection",
                name: "Model",
                description: "Select the Gemma model variant to use",
                type: .selection(availableModels.map { $0.name }),
                defaultValue: availableModels.first?.name ?? "",
                currentValue: selectedModel?.name ?? "",
                isRequired: true
            ),
            AIProviderSetting(
                id: "privacy_mode",
                name: "Enhanced Privacy",
                description: "Enable additional privacy protections",
                type: .boolean,
                defaultValue: true,
                currentValue: privacyManager.encryptionEnabled,
                isRequired: false
            ),
        ]
    }

    func updateSetting(_ setting: AIProviderSetting, value: Any) throws {
        switch setting.id {
        case "model_selection":
            guard let modelName = value as? String,
                let model = availableModels.first(where: { $0.name == modelName })
            else {
                throw AIProviderError.invalidConfiguration("Invalid model selection")
            }
            selectedModel = model

        case "privacy_mode":
            guard let enabled = value as? Bool else {
                throw AIProviderError.invalidConfiguration("Privacy mode must be boolean")
            }
            privacyManager.encryptionEnabled = enabled

        default:
            throw AIProviderError.unsupportedOperation("Unknown setting: \(setting.id)")
        }
    }

    // MARK: - Conversation Management

    func resetConversation() async {
        await gemmaService.resetConversation()
        AppLog.debug("Local MLX conversation state reset")
    }

    func getUsageStatistics() -> AIUsageStatistics {
        return usageStats
    }

    // MARK: - Private Methods

    private func validateHardware() throws {
        switch aiConfiguration.framework {
        case .mlx:
            guard HardwareDetector.isAppleSilicon else {
                throw AIProviderError.invalidConfiguration("MLX requires Apple Silicon")
            }
        case .llamaCpp:
            // Intel Macs supported with llama.cpp
            break
        }

        guard HardwareDetector.totalMemoryGB >= 8 else {
            throw AIProviderError.invalidConfiguration("Minimum 8GB RAM required")
        }
    }

    private func updateUsageStats(
        tokenCount: Int,
        responseTime: TimeInterval,
        error: Bool = false
    ) {
        usageStats = AIUsageStatistics(
            requestCount: usageStats.requestCount + 1,
            tokenCount: usageStats.tokenCount + tokenCount,
            averageResponseTime: (usageStats.averageResponseTime + responseTime) / 2,
            errorCount: usageStats.errorCount + (error ? 1 : 0),
            lastUsed: Date(),
            estimatedCost: nil  // Local models have no cost
        )
    }

    // MARK: - Dynamic Model Discovery

    /// Load available models from discovery service
    @MainActor
    private func loadAvailableModels() async {
        // Get discovered models from the discovery service
        let discoveredModels = modelDiscovery.discoveredModels

        // Convert discovered models to AIModel format
        var models: [AIModel] = []

        for discoveredModel in discoveredModels {
            let aiModel = AIModel(
                id: discoveredModel.id,
                name: discoveredModel.name,
                description: createModelDescription(from: discoveredModel),
                contextWindow: discoveredModel.metadata?.contextWindow ?? 8192,
                costPerToken: nil,
                pricing: nil,
                capabilities: getModelCapabilities(for: discoveredModel.modelType),
                provider: "local_mlx",
                isAvailable: discoveredModel.isValid
            )
            models.append(aiModel)
        }

        // If no models discovered, use fallback models
        if models.isEmpty {
            models = fallbackModels
            AppLog.debug("No local models discovered; using fallback models")
        }

        availableModels = models

        // Set default selected model
        if let savedModelId = UserDefaults.standard.string(forKey: "localMLXSelectedModel"),
            let model = availableModels.first(where: { $0.id == savedModelId })
        {
            selectedModel = model
        } else {
            selectedModel = availableModels.first
        }

        AppLog.debug("Loaded available local models: \(availableModels.count)")
    }

    /// Refresh model list by rescanning
    func refreshModels() async {
        await modelDiscovery.scanForModels()
        await loadAvailableModels()
    }

    /// Add a user model directory
    func addUserModelDirectory(_ path: String) async {
        await modelDiscovery.addUserModelPath(path)
        await loadAvailableModels()
    }

    /// Remove a user model directory
    func removeUserModelDirectory(_ path: String) async {
        await modelDiscovery.removeUserModelPath(path)
        await loadAvailableModels()
    }

    /// Get user-added model directories
    func getUserModelDirectories() -> [String] {
        return modelDiscovery.getUserModelPaths()
    }

    private func createModelDescription(from discoveredModel: ModelDiscoveryService.DiscoveredModel)
        -> String
    {
        var description = "\(discoveredModel.modelType.displayName) model"

        if let quantization = discoveredModel.metadata?.quantization {
            description += " (\(quantization))"
        }

        description += " - \(String(format: "%.1f", discoveredModel.sizeGB)) GB"
        description += " - \(discoveredModel.source.displayName)"

        return description
    }

    private func getModelCapabilities(
        for modelType: ModelDiscoveryService.DiscoveredModel.ModelType
    ) -> [AICapability] {
        switch modelType {
        case .gemma:
            return [.textGeneration, .conversation, .summarization]
        case .llama:
            return [.textGeneration, .conversation, .summarization, .codeGeneration]
        case .mistral:
            return [.textGeneration, .conversation, .codeGeneration]
        case .phi:
            return [.textGeneration, .conversation]
        case .unknown:
            return [.textGeneration, .conversation]
        }
    }
}

// MARK: - Hardware Requirements Extension

extension HardwareDetector {
    /// Check if current hardware meets MLX requirements
    static var isMLXCompatible: Bool {
        return isAppleSilicon && totalMemoryGB >= 8
    }

    /// Get recommended configuration based on hardware
    static func getRecommendedLocalConfig() -> (model: String, quantization: String) {
        if totalMemoryGB >= 16 {
            return ("gemma3_2B_4bit", "4-bit")
        } else {
            return ("gemma3_2B_4bit", "4-bit")  // Conservative for 8GB systems
        }
    }
}
