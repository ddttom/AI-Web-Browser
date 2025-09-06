import Foundation

/// Ollama local AI provider implementing the AIProvider protocol
/// Provides unified interface for Ollama models running locally
@MainActor
class OllamaProvider: AIProvider, ObservableObject {

    // MARK: - AIProvider Implementation

    let providerId = "ollama"
    let displayName = "Ollama (Local)"
    let providerType = AIProviderType.local

    @Published var isInitialized: Bool = false
    @Published var availableModels: [AIModel] = []

    var selectedModel: AIModel? {
        didSet {
            if let model = selectedModel {
                UserDefaults.standard.set(model.id, forKey: "ollamaSelectedModel")
            }
        }
    }

    // MARK: - Configuration

    private struct OllamaConfig {
        static let defaultHost = "127.0.0.1"
        static let defaultPort = 11434
        static let connectionTimeoutSeconds: TimeInterval = 10.0
        static let requestTimeoutSeconds: TimeInterval = 120.0
    }

    private var baseURL: URL {
        let host = UserDefaults.standard.string(forKey: "ollamaHost") ?? OllamaConfig.defaultHost
        let port = UserDefaults.standard.integer(forKey: "ollamaPort")
        let portToUse = port > 0 ? port : OllamaConfig.defaultPort
        return URL(string: "http://\(host):\(portToUse)")!
    }

    // MARK: - Private Properties

    private var usageStats = AIUsageStatistics(
        requestCount: 0,
        tokenCount: 0,
        averageResponseTime: 0,
        errorCount: 0,
        lastUsed: nil,
        estimatedCost: nil
    )

    private let session: URLSession

    // MARK: - Initialization

    init() {
        // Configure URLSession for Ollama API
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = OllamaConfig.requestTimeoutSeconds
        config.timeoutIntervalForResource = OllamaConfig.requestTimeoutSeconds
        self.session = URLSession(configuration: config)

        AppLog.debug("Ollama Provider initialized")
        
        // Load models asynchronously
        Task {
            await loadAvailableModels()
        }
    }

    // MARK: - Lifecycle Methods

    func initialize() async throws {
        do {
            // Check if Ollama service is running
            try await validateOllamaConnection()
            
            // Load available models
            await loadAvailableModels()

            guard !availableModels.isEmpty else {
                throw AIProviderError.invalidConfiguration(
                    "No Ollama models available. Run 'ollama pull <model>' to download models.")
            }

            isInitialized = true
            AppLog.debug("Ollama Provider initialized successfully")

        } catch {
            isInitialized = false
            throw AIProviderError.invalidConfiguration(
                "Ollama initialization failed: \(error.localizedDescription)")
        }
    }

    func isReady() async -> Bool {
        guard isInitialized else { return false }
        
        do {
            try await validateOllamaConnection()
            return !availableModels.isEmpty
        } catch {
            return false
        }
    }

    func cleanup() async {
        isInitialized = false
        availableModels = []
        selectedModel = nil
        AppLog.debug("Ollama Provider cleaned up")
    }

    // MARK: - Core AI Methods

    func generateResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage],
        model: AIModel?
    ) async throws -> AIResponse {
        let startTime = Date()
        let modelId = model?.id ?? selectedModel?.id ?? availableModels.first?.id
        
        guard let modelId = modelId else {
            throw AIProviderError.modelNotAvailable("No model selected")
        }

        do {
            let prompt = buildPrompt(query: query, context: context, history: conversationHistory)
            let response = try await sendOllamaRequest(
                model: modelId,
                prompt: prompt,
                stream: false
            )

            guard let responseText = response["response"] as? String else {
                throw AIProviderError.providerSpecificError("Invalid response format from Ollama")
            }

            let responseTime = Date().timeIntervalSince(startTime)
            let tokenCount = estimateTokenCount(responseText)

            updateUsageStats(
                tokenCount: tokenCount,
                responseTime: responseTime,
                error: false
            )

            return AIResponse(
                text: responseText,
                model: selectedModel ?? AIModel.defaultLocal,
                usage: nil,
                processingTime: responseTime
            )

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
        let modelId = model?.id ?? selectedModel?.id ?? availableModels.first?.id
        
        guard let modelId = modelId else {
            throw AIProviderError.modelNotAvailable("No model selected")
        }

        let prompt = buildPrompt(query: query, context: context, history: conversationHistory)
        let startTime = Date()

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var totalTokens = 0
                    try await streamOllamaRequest(
                        model: modelId,
                        prompt: prompt
                    ) { chunk in
                        if let response = chunk["response"] as? String, !response.isEmpty {
                            totalTokens += estimateTokenCount(response)
                            continuation.yield(response)
                        }
                    }

                    let responseTime = Date().timeIntervalSince(startTime)
                    updateUsageStats(
                        tokenCount: totalTokens,
                        responseTime: responseTime,
                        error: false
                    )
                    continuation.finish()

                } catch {
                    let responseTime = Date().timeIntervalSince(startTime)
                    updateUsageStats(tokenCount: 0, responseTime: responseTime, error: true)
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
        let modelId = model?.id ?? selectedModel?.id ?? availableModels.first?.id
        
        guard let modelId = modelId else {
            throw AIProviderError.modelNotAvailable("No model selected")
        }

        do {
            let response = try await sendOllamaRequest(
                model: modelId,
                prompt: prompt,
                stream: false
            )

            guard let responseText = response["response"] as? String else {
                throw AIProviderError.providerSpecificError("Invalid response format from Ollama")
            }

            let responseTime = Date().timeIntervalSince(startTime)
            let tokenCount = estimateTokenCount(responseText)

            updateUsageStats(
                tokenCount: tokenCount,
                responseTime: responseTime,
                error: false
            )

            return responseText

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
        let conversationText = messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
        let prompt = "Summarize this conversation concisely:\n\n\(conversationText)\n\nSummary:"
        
        return try await generateRawResponse(prompt: prompt, model: model)
    }

    // MARK: - Configuration Methods

    func validateConfiguration() async throws {
        try await validateOllamaConnection()
    }

    func getConfigurableSettings() -> [AIProviderSetting] {
        return [
            AIProviderSetting(
                id: "model_selection",
                name: "Model",
                description: "Select the Ollama model to use",
                type: .selection(availableModels.map { $0.name }),
                defaultValue: availableModels.first?.name ?? "",
                currentValue: selectedModel?.name ?? "",
                isRequired: true
            ),
            AIProviderSetting(
                id: "ollama_host",
                name: "Ollama Host",
                description: "Hostname or IP address where Ollama is running",
                type: .string,
                defaultValue: OllamaConfig.defaultHost,
                currentValue: UserDefaults.standard.string(forKey: "ollamaHost") ?? OllamaConfig.defaultHost,
                isRequired: true
            ),
            AIProviderSetting(
                id: "ollama_port",
                name: "Ollama Port",
                description: "Port number where Ollama is listening",
                type: .number,
                defaultValue: OllamaConfig.defaultPort,
                currentValue: UserDefaults.standard.integer(forKey: "ollamaPort") > 0 ? 
                    UserDefaults.standard.integer(forKey: "ollamaPort") : OllamaConfig.defaultPort,
                isRequired: true
            )
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

        case "ollama_host":
            guard let host = value as? String, !host.isEmpty else {
                throw AIProviderError.invalidConfiguration("Ollama host cannot be empty")
            }
            UserDefaults.standard.set(host, forKey: "ollamaHost")

        case "ollama_port":
            guard let port = value as? Int, port > 0, port <= 65535 else {
                throw AIProviderError.invalidConfiguration("Port must be between 1 and 65535")
            }
            UserDefaults.standard.set(port, forKey: "ollamaPort")

        default:
            throw AIProviderError.unsupportedOperation("Unknown setting: \(setting.id)")
        }
    }

    // MARK: - Conversation Management

    func resetConversation() async {
        // Ollama is stateless by default, so no action needed
        AppLog.debug("Ollama conversation state reset (no-op)")
    }

    func getUsageStatistics() -> AIUsageStatistics {
        return usageStats
    }

    // MARK: - Private Methods

    private func validateOllamaConnection() async throws {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = OllamaConfig.connectionTimeoutSeconds

        do {
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIProviderError.networkError(NSError(
                    domain: "OllamaProvider",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid response from Ollama service"]
                ))
            }

            guard httpResponse.statusCode == 200 else {
                throw AIProviderError.providerSpecificError(
                    "Ollama service unavailable (HTTP \(httpResponse.statusCode)). Ensure Ollama is running."
                )
            }

        } catch let error as URLError where error.code == .timedOut {
            throw AIProviderError.providerSpecificError(
                "Cannot connect to Ollama at \(baseURL.absoluteString). Check if Ollama is running and accessible."
            )
        } catch {
            throw AIProviderError.networkError(error)
        }
    }

    private func loadAvailableModels() async {
        do {
            let url = baseURL.appendingPathComponent("api/tags")
            var request = URLRequest(url: url)
            request.timeoutInterval = OllamaConfig.connectionTimeoutSeconds

            let (data, _) = try await session.data(for: request)
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else {
                AppLog.debug("No models found in Ollama response")
                return
            }

            var aiModels: [AIModel] = []
            
            for modelData in models {
                guard let name = modelData["name"] as? String else { continue }
                
                let size = modelData["size"] as? Int64 ?? 0
                let sizeGB = Double(size) / (1024 * 1024 * 1024)
                
                let aiModel = AIModel(
                    id: name,
                    name: name,
                    description: "Ollama model - \(String(format: "%.1f", sizeGB)) GB",
                    contextWindow: getContextWindow(for: name),
                    costPerToken: nil,
                    pricing: nil,
                    capabilities: getCapabilities(for: name),
                    provider: providerId,
                    isAvailable: true
                )
                
                aiModels.append(aiModel)
            }

            await MainActor.run {
                self.availableModels = aiModels
                
                // Set default selected model if none is set
                if let savedModelId = UserDefaults.standard.string(forKey: "ollamaSelectedModel"),
                   let model = availableModels.first(where: { $0.id == savedModelId }) {
                    selectedModel = model
                } else {
                    selectedModel = availableModels.first
                }
                
                AppLog.debug("Loaded \(aiModels.count) Ollama models")
            }

        } catch {
            AppLog.error("Failed to load Ollama models: \(error.localizedDescription)")
        }
    }

    private func sendOllamaRequest(
        model: String,
        prompt: String,
        stream: Bool
    ) async throws -> [String: Any] {
        let url = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": stream
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.networkError(NSError(
                domain: "OllamaProvider",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response"]
            ))
        }

        guard httpResponse.statusCode == 200 else {
            throw AIProviderError.providerSpecificError(
                "Ollama request failed with HTTP \(httpResponse.statusCode)"
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.providerSpecificError("Invalid JSON response from Ollama")
        }

        return json
    }

    private func streamOllamaRequest(
        model: String,
        prompt: String,
        onChunk: @escaping ([String: Any]) -> Void
    ) async throws {
        let url = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (asyncBytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.networkError(NSError(
                domain: "OllamaProvider",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response"]
            ))
        }

        guard httpResponse.statusCode == 200 else {
            throw AIProviderError.providerSpecificError(
                "Ollama stream request failed with HTTP \(httpResponse.statusCode)"
            )
        }

        var buffer = Data()
        
        for try await byte in asyncBytes {
            buffer.append(byte)
            
            // Process complete lines
            while let newlineRange = buffer.range(of: Data([0x0A])) { // \n
                let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
                buffer.removeSubrange(0..<newlineRange.upperBound)
                
                if !lineData.isEmpty {
                    do {
                        if let json = try JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                            onChunk(json)
                            
                            // Check if this is the final chunk
                            if let done = json["done"] as? Bool, done {
                                return
                            }
                        }
                    } catch {
                        // Skip invalid JSON lines
                        continue
                    }
                }
            }
        }
    }

    private func buildPrompt(
        query: String,
        context: String?,
        history: [ConversationMessage]
    ) -> String {
        var prompt = ""

        // Add context if available
        if let context = context, !context.isEmpty {
            prompt += "Context: \(context)\n\n"
        }

        // Add recent conversation history (limit to avoid token overflow)
        let recentHistory = Array(history.suffix(5))
        for message in recentHistory {
            prompt += "\(message.role.capitalized): \(message.content)\n"
        }

        // Add current query
        prompt += "User: \(query)\nAssistant: "

        return prompt
    }

    private func estimateTokenCount(_ text: String) -> Int {
        // Rough estimation: 1 token ≈ 3.5 characters
        return Int(Double(text.count) / 3.5)
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
            estimatedCost: nil // Local models have no cost
        )
    }

    private func getContextWindow(for modelName: String) -> Int {
        // Set context window based on known model types
        let lowercaseName = modelName.lowercased()
        
        if lowercaseName.contains("llama3") {
            return 8192
        } else if lowercaseName.contains("llama2") {
            return 4096
        } else if lowercaseName.contains("gemma") {
            return 8192
        } else if lowercaseName.contains("mistral") {
            return 8192
        } else if lowercaseName.contains("codellama") {
            return 16384
        } else {
            return 4096 // Conservative default
        }
    }

    private func getCapabilities(for modelName: String) -> [AICapability] {
        let lowercaseName = modelName.lowercased()
        
        var capabilities: [AICapability] = [.textGeneration, .conversation]
        
        if lowercaseName.contains("code") {
            capabilities.append(.codeGeneration)
        }
        
        capabilities.append(.summarization)
        
        return capabilities
    }
}

// MARK: - Refresh Models Method

extension OllamaProvider {
    /// Refresh the list of available models
    func refreshModels() async {
        await loadAvailableModels()
    }
    
    /// Quick availability check for smart initialization
    static func isServiceRunning(host: String = "127.0.0.1", port: Int = 11434) async -> Bool {
        do {
            let baseURL = URL(string: "http://\(host):\(port)")!
            let url = baseURL.appendingPathComponent("api/tags")
            var request = URLRequest(url: url)
            request.timeoutInterval = 2.0 // Very quick check
            
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 2.0
            let session = URLSession(configuration: config)
            
            let (_, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
            
        } catch {
            return false
        }
    }
}