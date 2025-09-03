import Foundation

/// Anthropic Claude provider implementing the AIProvider protocol
/// Supports Claude models with streaming and advanced reasoning
@MainActor
class AnthropicProvider: ExternalAPIProvider {

    // MARK: - AIProvider Implementation

    override var providerId: String { "anthropic" }
    override var displayName: String { "Anthropic Claude" }

    // MARK: - Anthropic Configuration

    private let baseURL = "https://api.anthropic.com/v1"
    private let userAgent = "Web-Browser/1.0"
    private let anthropicVersion = "2023-06-01"

    // MARK: - Rate Limiting

    private var lastRequestTime: Date = Date.distantPast
    private let minimumRequestInterval: TimeInterval = 0.2  // 5 requests per second max

    init() {
        super.init(apiProviderType: .anthropic)
    }

    // MARK: - Model Management

    override func loadAvailableModels() async {
        availableModels = [
            AIModel(
                id: "claude-4-sonnet-latest",
                name: "Claude 4 Sonnet (latest)",
                description: "Most capable Claude model, excellent for complex tasks and reasoning",
                contextWindow: 200000,
                costPerToken: nil,
                pricing: ModelPricing(
                    inputPerMTokensUSD: 3.0,  // placeholder
                    outputPerMTokensUSD: 15.0,  // placeholder
                    cachedInputPerMTokensUSD: nil
                ),
                capabilities: [
                    .textGeneration, .conversation, .summarization, .codeGeneration, .imageAnalysis,
                    .functionCalling,
                ],
                provider: providerId,
                isAvailable: true
            ),
            AIModel(
                id: "claude-4-haiku-latest",
                name: "Claude 4 Haiku (latest)",
                description: "Fastest Claude model, optimized for quick responses",
                contextWindow: 200000,
                costPerToken: nil,
                pricing: ModelPricing(
                    inputPerMTokensUSD: 0.25,  // placeholder
                    outputPerMTokensUSD: 1.25,  // placeholder
                    cachedInputPerMTokensUSD: nil
                ),
                capabilities: [.textGeneration, .conversation, .summarization, .codeGeneration],
                provider: providerId,
                isAvailable: true
            ),
            AIModel(
                id: "claude-4-opus-latest",
                name: "Claude 4 Opus (latest)",
                description: "Most powerful Claude model for the most complex tasks",
                contextWindow: 200000,
                costPerToken: nil,
                pricing: ModelPricing(
                    inputPerMTokensUSD: 15.0,  // placeholder
                    outputPerMTokensUSD: 75.0,  // placeholder
                    cachedInputPerMTokensUSD: nil
                ),
                capabilities: [
                    .textGeneration, .conversation, .summarization, .codeGeneration, .imageAnalysis,
                    .functionCalling,
                ],
                provider: providerId,
                isAvailable: true
            ),
        ]

        // Set default model
        if selectedModel == nil {
            selectedModel =
                availableModels.first { $0.id == "claude-4-sonnet-latest" }
                ?? availableModels.first
        }

        AppLog.debug("Anthropic models loaded: \(availableModels.count)")
    }

    // MARK: - Configuration Validation

    override func validateConfiguration() async throws {
        guard apiKey != nil else {
            throw AIProviderError.missingAPIKey(displayName)
        }

        // Test API key with a simple request
        let testPayload: [String: Any] = [
            "model": "claude-4-haiku-latest",
            "max_tokens": 5,
            "messages": [
                ["role": "user", "content": "Hi"]
            ],
        ]

        do {
            let _ = try await makeAPIRequest(
                endpoint: "/messages",
                payload: testPayload
            )
            AppLog.debug("Anthropic API key validated")
        } catch {
            throw AIProviderError.authenticationFailed
        }
    }

    // MARK: - Core AI Methods

    override func generateResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage],
        model: AIModel?
    ) async throws -> AIResponse {
        let startTime = Date()
        let modelId = model?.id ?? selectedModel?.id ?? "claude-4-sonnet-latest"

        // Apply rate limiting
        await applyRateLimit()

        // Build messages (respect per-provider context sharing preference)
        let effectiveContext = isContextSharingEnabled() ? context : nil
        let messages = buildMessages(
            query: query, context: effectiveContext, history: conversationHistory)

        var payload: [String: Any] = [
            "model": modelId,
            "max_tokens": 4096,
            "messages": messages,
        ]

        // Add system message if we have context
        if let context = context, !context.isEmpty {
            payload["system"] =
                "You are a helpful assistant. Answer questions based on the provided webpage content:\n\n\(context)"
        }

        do {
            let response = try await makeAPIRequest(
                endpoint: "/messages",
                payload: payload
            )

            guard let content = response["content"] as? [[String: Any]],
                let firstContent = content.first,
                let text = firstContent["text"] as? String
            else {
                throw AIProviderError.providerSpecificError(
                    "Invalid response format from Anthropic")
            }

            // Extract usage information
            var tokenCount = 0
            var cost: Double? = nil
            var inputTokens = 0
            var outputTokens = 0

            if let usage = response["usage"] as? [String: Any] {
                inputTokens = usage["input_tokens"] as? Int ?? 0
                outputTokens = usage["output_tokens"] as? Int ?? 0
                tokenCount = inputTokens + outputTokens
                cost = estimateCostUSD(
                    forModelId: modelId, promptTokens: inputTokens, completionTokens: outputTokens)
            }

            let responseTime = Date().timeIntervalSince(startTime)
            updateUsageStats(
                tokenCount: tokenCount,
                responseTime: responseTime,
                cost: cost,
                error: false
            )
            // Persist usage event
            AIUsageStore.shared.append(
                providerId: providerId,
                modelId: modelId,
                promptTokens: inputTokens,
                completionTokens: outputTokens,
                estimatedCostUSD: cost,
                success: true,
                latencyMs: Int(responseTime * 1000),
                contextIncluded: (context != nil)
            )

            // Create metadata for external API response
            let metadata = ResponseMetadata(
                modelVersion: modelId,
                inferenceMethod: .fallback,
                contextUsed: context != nil,
                processingSteps: [],
                memoryUsage: 0,
                energyImpact: responseTime > 5.0 ? .moderate : .low
            )

            // Return AIResponse compatible with existing system
            return AIResponse(
                text: text,
                processingTime: responseTime,
                tokenCount: tokenCount,
                metadata: metadata
            )

        } catch {
            let responseTime = Date().timeIntervalSince(startTime)
            updateUsageStats(tokenCount: 0, responseTime: responseTime, error: true)
            throw handleAPIError(error)
        }
    }

    override func generateStreamingResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage],
        model: AIModel?
    ) async throws -> AsyncThrowingStream<String, Error> {
        let modelId = model?.id ?? selectedModel?.id ?? "claude-4-sonnet-latest"

        // Apply rate limiting
        await applyRateLimit()

        // Build messages (respect per-provider context sharing preference)
        let effectiveContext = isContextSharingEnabled() ? context : nil
        let messages = buildMessages(
            query: query, context: effectiveContext, history: conversationHistory)

        var payload: [String: Any] = [
            "model": modelId,
            "max_tokens": 4096,
            "messages": messages,
            "stream": true,
        ]

        // Add system message if we have context
        if let context = context, !context.isEmpty {
            payload["system"] =
                "You are a helpful assistant. Answer questions based on the provided webpage content:\n\n\(context)"
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let startTime = Date()
                    var charCount = 0
                    let stream = try await makeStreamingAPIRequest(
                        endpoint: "/messages",
                        payload: payload
                    )

                    var completionText = ""
                    for try await chunk in stream {
                        charCount += chunk.count
                        completionText += chunk
                        continuation.yield(chunk)
                    }

                    // Log usage on finish (estimate tokens on streaming)
                    let estTokens = Int((Double(charCount) / 4.0).rounded())
                    let responseTime = Date().timeIntervalSince(startTime)
                    let estCost = estimateCostUSD(
                        forModelId: modelId, promptTokens: 0, completionTokens: estTokens)
                    // Update in-memory stats for settings view
                    updateUsageStats(
                        tokenCount: estTokens,
                        responseTime: responseTime,
                        cost: estCost,
                        error: false
                    )
                    AIUsageStore.shared.append(
                        providerId: providerId,
                        modelId: modelId,
                        promptTokens: 0,
                        completionTokens: estTokens,
                        estimatedCostUSD: estCost,
                        success: true,
                        latencyMs: Int(responseTime * 1000),
                        contextIncluded: (context != nil)
                    )

                    continuation.finish()

                } catch {
                    continuation.finish(throwing: handleAPIError(error))
                }
            }
        }
    }

    override func generateRawResponse(
        prompt: String,
        model: AIModel?
    ) async throws -> String {
        let modelId = model?.id ?? selectedModel?.id ?? "claude-4-sonnet-latest"

        await applyRateLimit()

        let payload: [String: Any] = [
            "model": modelId,
            "max_tokens": 2048,
            "messages": [
                ["role": "user", "content": prompt]
            ],
        ]

        let response = try await makeAPIRequest(
            endpoint: "/messages",
            payload: payload
        )

        guard let content = response["content"] as? [[String: Any]],
            let firstContent = content.first,
            let text = firstContent["text"] as? String
        else {
            throw AIProviderError.providerSpecificError("Invalid response format from Anthropic")
        }

        return text
    }

    override func summarizeConversation(
        _ messages: [ConversationMessage],
        model: AIModel?
    ) async throws -> String {
        let conversationText = messages.map { "\($0.role.description): \($0.content)" }.joined(
            separator: "\n")

        let summaryPrompt = """
            Summarize the following conversation in 2-3 sentences, focusing on the main topics and outcomes:

            \(conversationText)

            Summary:
            """

        return try await generateRawResponse(prompt: summaryPrompt, model: model)
    }

    // MARK: - API Communication

    private func makeAPIRequest(
        endpoint: String,
        payload: [String: Any]
    ) async throws -> [String: Any] {
        // Circuit breaker
        try preflightCircuitBreaker()

        guard apiKey != nil else {
            throw AIProviderError.missingAPIKey(displayName)
        }

        guard let url = URL(string: baseURL + endpoint) else {
            throw AIProviderError.invalidConfiguration("Invalid API endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw AIProviderError.invalidConfiguration("Failed to serialize request")
        }

        var lastError: Error?
        var lastStatus: Int?
        var lastResponse: HTTPURLResponse?
        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AIProviderError.networkError(URLError(.badServerResponse))
                }
                lastResponse = httpResponse

                switch httpResponse.statusCode {
                case 200...299:
                    recordRequestSuccess()
                    do {
                        guard
                            let json = try JSONSerialization.jsonObject(with: data)
                                as? [String: Any]
                        else {
                            throw AIProviderError.providerSpecificError("Invalid JSON response")
                        }
                        return json
                    } catch {
                        throw AIProviderError.providerSpecificError("Failed to parse response")
                    }
                case 401:
                    recordRequestFailure(httpStatus: 401)
                    throw AIProviderError.authenticationFailed
                case 429, 500, 502, 503, 504:
                    lastStatus = httpResponse.statusCode
                    if attempt < maxAttempts {
                        let delay = backoffDelayForAttempt(attempt, response: httpResponse)
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    } else {
                        recordRequestFailure(httpStatus: httpResponse.statusCode)
                        throw AIProviderError.providerSpecificError(
                            "HTTP \(httpResponse.statusCode)")
                    }
                default:
                    recordRequestFailure(httpStatus: httpResponse.statusCode)
                    throw AIProviderError.providerSpecificError("HTTP \(httpResponse.statusCode)")
                }
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    let delay = backoffDelayForAttempt(attempt, response: lastResponse)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                } else {
                    recordRequestFailure(httpStatus: lastStatus)
                    throw handleAPIError(error)
                }
            }
        }
        recordRequestFailure(httpStatus: lastStatus)
        throw lastError ?? AIProviderError.providerSpecificError("Unknown error")
    }

    private func makeStreamingAPIRequest(
        endpoint: String,
        payload: [String: Any]
    ) async throws -> AsyncThrowingStream<String, Error> {
        // Circuit breaker
        try preflightCircuitBreaker()

        guard apiKey != nil else {
            throw AIProviderError.missingAPIKey(displayName)
        }

        guard let url = URL(string: baseURL + endpoint) else {
            throw AIProviderError.invalidConfiguration("Invalid API endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                        httpResponse.statusCode == 200
                    else {
                        recordRequestFailure(httpStatus: (response as? HTTPURLResponse)?.statusCode)
                        throw AIProviderError.networkError(URLError(.badServerResponse))
                    }

                    recordRequestSuccess()
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let data = String(line.dropFirst(6))

                            if let jsonData = data.data(using: .utf8),
                                let json = try? JSONSerialization.jsonObject(with: jsonData)
                                    as? [String: Any]
                            {

                                // Handle different event types
                                if let type = json["type"] as? String {
                                    switch type {
                                    case "content_block_delta":
                                        if let delta = json["delta"] as? [String: Any],
                                            let text = delta["text"] as? String
                                        {
                                            continuation.yield(text)
                                        }
                                    case "message_stop":
                                        // End of stream
                                        break
                                    default:
                                        // Ignore other event types
                                        break
                                    }
                                }
                            }
                        }
                    }

                    continuation.finish()

                } catch {
                    continuation.finish(throwing: handleAPIError(error))
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func buildMessages(
        query: String,
        context: String?,
        history: [ConversationMessage]
    ) -> [[String: Any]] {
        var messages: [[String: Any]] = []

        // Recent conversation history (last 10 messages)
        let recentHistory = Array(history.suffix(10))
        for message in recentHistory {
            let role = message.role == .user ? "user" : "assistant"
            messages.append([
                "role": role,
                "content": [
                    ["type": "text", "text": message.content]
                ],
            ])
        }

        // Current query
        let queryContent: [[String: Any]] = [
            ["type": "text", "text": query]
        ]

        messages.append([
            "role": "user",
            "content": queryContent,
        ])

        return messages
    }

    private func applyRateLimit() async {
        let timeSinceLastRequest = Date().timeIntervalSince(lastRequestTime)
        if timeSinceLastRequest < minimumRequestInterval {
            let delay = minimumRequestInterval - timeSinceLastRequest
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        lastRequestTime = Date()
    }

    private func handleAPIError(_ error: Error) -> Error {
        if let urlError = error as? URLError {
            return AIProviderError.networkError(urlError)
        }
        return AIProviderError.providerSpecificError(error.localizedDescription)
    }

    // MARK: - Settings

    override func getConfigurableSettings() -> [AIProviderSetting] {
        return [
            AIProviderSetting(
                id: "model_selection",
                name: "Model",
                description: "Select the Claude model to use",
                type: .selection(availableModels.map { $0.name }),
                defaultValue: "Claude 3.5 Sonnet",
                currentValue: selectedModel?.name ?? "Claude 3.5 Sonnet",
                isRequired: true
            ),
            AIProviderSetting(
                id: "max_tokens",
                name: "Max Tokens",
                description: "Maximum tokens in response (1-4096)",
                type: .number,
                defaultValue: 4096,
                currentValue: 4096,
                isRequired: false
            ),
        ]
    }
}
