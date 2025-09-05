import Foundation

/// OpenAI provider implementing the AIProvider protocol
/// Supports GPT models with streaming and function calling
@MainActor
class OpenAIProvider: ExternalAPIProvider {

    // MARK: - AIProvider Implementation

    override var providerId: String { "openai" }
    override var displayName: String { "OpenAI GPT" }

    // MARK: - OpenAI Configuration

    private let baseURL = "https://api.openai.com/v1"
    private let userAgent = "Web-Browser/1.0"

    // MARK: - Rate Limiting

    private var lastRequestTime: Date = Date.distantPast
    private let minimumRequestInterval: TimeInterval = 0.1  // 10 requests per second max

    init() {
        super.init(apiProviderType: .openai)
    }

    // MARK: - Model Management

    override func loadAvailableModels() async {
        availableModels = [
            // GPT-5 family
            AIModel(
                id: "gpt-5",
                name: "GPT-5",
                description: "Latest flagship model for reasoning and complex tasks",
                contextWindow: 200_000,
                costPerToken: nil,
                pricing: ModelPricing(
                    inputPerMTokensUSD: 5.00,
                    outputPerMTokensUSD: 15.00,
                    cachedInputPerMTokensUSD: 2.50
                ),
                capabilities: [
                    .textGeneration, .conversation, .summarization, .codeGeneration,
                    .functionCalling, .imageAnalysis,
                ],
                provider: providerId,
                isAvailable: true
            ),
            AIModel(
                id: "gpt-5-mini",
                name: "GPT-5 Mini",
                description: "Fast and affordable general-purpose model",
                contextWindow: 200_000,
                costPerToken: nil,
                pricing: ModelPricing(
                    inputPerMTokensUSD: 0.60,
                    outputPerMTokensUSD: 2.40,
                    cachedInputPerMTokensUSD: 0.30
                ),
                capabilities: [
                    .textGeneration, .conversation, .summarization, .codeGeneration,
                    .functionCalling,
                ],
                provider: providerId,
                isAvailable: true
            ),
            AIModel(
                id: "gpt-5-nano",
                name: "GPT-5 Nano",
                description: "Lowest-latency and most economical GPT-5 variant",
                contextWindow: 200_000,
                costPerToken: nil,
                pricing: ModelPricing(
                    inputPerMTokensUSD: 0.20,
                    outputPerMTokensUSD: 0.80,
                    cachedInputPerMTokensUSD: 0.10
                ),
                capabilities: [.textGeneration, .conversation, .summarization, .codeGeneration],
                provider: providerId,
                isAvailable: true
            ),

            // GPT-4o family (kept for stability)
            AIModel(
                id: "gpt-4o-mini",
                name: "GPT-4o Mini",
                description: "Fast, low-cost omni model ideal for most tasks",
                contextWindow: 200_000,
                costPerToken: nil,
                pricing: ModelPricing(
                    inputPerMTokensUSD: 0.60,
                    outputPerMTokensUSD: 2.40,
                    cachedInputPerMTokensUSD: 0.30
                ),
                capabilities: [
                    .textGeneration, .conversation, .summarization, .codeGeneration,
                    .functionCalling, .imageAnalysis,
                ],
                provider: providerId,
                isAvailable: true
            ),
            AIModel(
                id: "gpt-4o",
                name: "GPT-4o",
                description: "General‑purpose omni model with high quality",
                contextWindow: 200_000,
                costPerToken: nil,
                pricing: ModelPricing(
                    inputPerMTokensUSD: 5.00,
                    outputPerMTokensUSD: 15.00,
                    cachedInputPerMTokensUSD: 2.50
                ),
                capabilities: [
                    .textGeneration, .conversation, .summarization, .codeGeneration,
                    .functionCalling, .imageAnalysis,
                ],
                provider: providerId,
                isAvailable: true
            ),
        ]

        // Set default model (prefer 5-mini if available)
        if selectedModel == nil {
            selectedModel =
                availableModels.first { $0.id == "gpt-5-mini" }
                ?? availableModels.first { $0.id == "gpt-4o-mini" }
                ?? availableModels.first
        }

        AppLog.debug("OpenAI models loaded: \(availableModels.count)")
    }

    // MARK: - Configuration Validation

    override func validateConfiguration() async throws {
        guard apiKey != nil else {
            throw AIProviderError.missingAPIKey(displayName)
        }

        // Test API key with a simple request to a generally available model
        let testModel = selectedModel?.id ?? "gpt-4o-mini"
        let testPayload: [String: Any] = [
            "model": testModel,
            "messages": [
                ["role": "user", "content": "ping"]
            ],
        ]

        do {
            let _ = try await makeAPIRequest(
                endpoint: "/chat/completions",
                payload: testPayload
            )
            AppLog.debug("OpenAI API key validated")
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
        let initialModelId = model?.id ?? selectedModel?.id ?? "gpt-5-mini"

        // Apply rate limiting
        await applyRateLimit()

        // Build messages (respect per-provider context sharing preference)
        let effectiveContext = isContextSharingEnabled() ? context : nil
        let messages = buildMessages(
            query: query, context: effectiveContext, history: conversationHistory)

        do {
            var basePayload: [String: Any] = [
                "messages": messages
            ]
            // Some GPT-5 endpoints only accept default sampling; avoid explicit params to prevent 400s
            if !initialModelId.hasPrefix("gpt-5") {
                basePayload["temperature"] = 0.7
                basePayload["top_p"] = 0.9
            }
            let tokensKey = isNewModelAPI(initialModelId) ? "max_completion_tokens" : "max_tokens"
            basePayload[tokensKey] = 2048

            let (response, usedModelId) = try await requestWithModelFallback(
                endpoint: "/chat/completions",
                baseModelId: initialModelId,
                basePayload: basePayload
            )

            guard let choices = response["choices"] as? [[String: Any]],
                let firstChoice = choices.first,
                let message = firstChoice["message"] as? [String: Any],
                let content = message["content"] as? String
            else {
                throw AIProviderError.providerSpecificError("Invalid response format from OpenAI")
            }

            // Extract usage information
            var promptTokens = 0
            var completionTokens = 0
            var tokenCount = 0
            var cost: Double? = nil

            if let usage = response["usage"] as? [String: Any] {
                promptTokens = usage["prompt_tokens"] as? Int ?? 0
                completionTokens = usage["completion_tokens"] as? Int ?? 0
                tokenCount = (usage["total_tokens"] as? Int) ?? (promptTokens + completionTokens)
                cost = estimateCostUSD(
                    forModelId: usedModelId, promptTokens: promptTokens,
                    completionTokens: completionTokens)
            }

            let responseTime = Date().timeIntervalSince(startTime)
            updateUsageStats(
                tokenCount: tokenCount,
                responseTime: responseTime,
                cost: cost,
                error: false
            )
            // Usage store event
            AIUsageStore.shared.append(
                providerId: providerId,
                modelId: usedModelId,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                estimatedCostUSD: cost,
                success: true,
                latencyMs: Int(responseTime * 1000),
                contextIncluded: (context != nil)
            )

            // Create metadata for external API response
            let metadata = ResponseMetadata(
                modelVersion: usedModelId,
                inferenceMethod: .fallback,
                contextUsed: context != nil,
                processingSteps: [],
                memoryUsage: 0,
                energyImpact: responseTime > 5.0 ? .moderate : .low
            )

            // Return AIResponse compatible with existing system
            return AIResponse(
                text: content,
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
        let initialModelId = model?.id ?? selectedModel?.id ?? "gpt-5-mini"

        // Apply rate limiting
        await applyRateLimit()

        // Build messages (respect per-provider context sharing preference)
        let effectiveContext = isContextSharingEnabled() ? context : nil
        let messages = buildMessages(
            query: query, context: effectiveContext, history: conversationHistory)

        func buildPayload(with modelId: String) -> [String: Any] {
            var payload: [String: Any] = [
                "model": modelId,
                "messages": messages,
                "stream": true,
            ]
            if !modelId.hasPrefix("gpt-5") {
                payload["temperature"] = 0.7
                payload["top_p"] = 0.9
            }
            let tokensKey = isNewModelAPI(modelId) ? "max_completion_tokens" : "max_tokens"
            payload[tokensKey] = 2048
            return payload
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let startTime = Date()
                    var charCount = 0
                    var attemptedModelId = initialModelId
                    var stream: AsyncThrowingStream<String, Error>!
                    do {
                        stream = try await makeStreamingAPIRequest(
                            endpoint: "/chat/completions",
                            payload: buildPayload(with: attemptedModelId)
                        )
                    } catch {
                        // Fallback strategy: try close siblings if model likely unsupported
                        let fallbackMatrix: [String: [String]] = [
                            "gpt-5": ["gpt-4o-mini", "gpt-4o"],
                            "gpt-4o-mini": ["gpt-4o"],
                            "gpt-4o": ["gpt-4o-mini"],
                        ]
                        var attempted = false
                        for (prefix, fallbacks) in fallbackMatrix {
                            if attemptedModelId.hasPrefix(prefix) {
                                for fid in fallbacks {
                                    do {
                                        attemptedModelId = fid
                                        stream = try await makeStreamingAPIRequest(
                                            endpoint: "/chat/completions",
                                            payload: buildPayload(with: fid)
                                        )
                                        AppLog.debug("OpenAI streaming fallback -> \(fid)")
                                        attempted = true
                                        break
                                    } catch {
                                        continue
                                    }
                                }
                                break
                            }
                        }
                        if !attempted { throw error }
                    }

                    for try await chunk in stream {
                        charCount += chunk.count
                        continuation.yield(chunk)
                    }

                    // Log usage on finish (estimate tokens on streaming)
                    let estTokens = Int((Double(charCount) / 4.0).rounded())
                    let responseTime = Date().timeIntervalSince(startTime)
                    let estCost = estimateCostUSD(
                        forModelId: attemptedModelId, promptTokens: 0, completionTokens: estTokens)
                    // Update in-memory stats for settings view
                    updateUsageStats(
                        tokenCount: estTokens,
                        responseTime: responseTime,
                        cost: estCost,
                        error: false
                    )
                    AIUsageStore.shared.append(
                        providerId: providerId,
                        modelId: attemptedModelId,
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
        let initialModelId = model?.id ?? selectedModel?.id ?? "gpt-5-mini"

        await applyRateLimit()

        var basePayload: [String: Any] = [
            "messages": [["role": "user", "content": prompt]]
        ]
        if !initialModelId.hasPrefix("gpt-5") {
            basePayload["temperature"] = 0.7
        }
        let tokensKey = isNewModelAPI(initialModelId) ? "max_completion_tokens" : "max_tokens"
        basePayload[tokensKey] = 1024
        let (response, _) = try await requestWithModelFallback(
            endpoint: "/chat/completions",
            baseModelId: initialModelId,
            basePayload: basePayload
        )

        guard let choices = response["choices"] as? [[String: Any]],
            let firstChoice = choices.first,
            let message = firstChoice["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw AIProviderError.providerSpecificError("Invalid response format from OpenAI")
        }

        return content
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
        payload: [String: Any],
        allowSamplingFallback: Bool = true
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
        request.setValue("Bearer \(apiKey ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
                    // Success
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
                    // Auth errors shouldn't be retried
                    recordRequestFailure(httpStatus: 401)
                    throw AIProviderError.authenticationFailed
                case 429, 500, 502, 503, 504:
                    lastStatus = httpResponse.statusCode
                    // Retry with backoff
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
                    // Log body for diagnostics (truncate to keep logs small)
                    let snippet = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                    let trimmed = snippet.prefix(500)
                    AppLog.warn("OpenAI HTTP \(httpResponse.statusCode): \(trimmed)")
                    recordRequestFailure(httpStatus: httpResponse.statusCode)

                    // Smart fallback: some models only accept default sampling parameters.
                    if httpResponse.statusCode == 400 && allowSamplingFallback,
                        OpenAIProvider.isTemperatureUnsupportedErrorBody(data)
                    {
                        var sanitized = payload
                        sanitized.removeValue(forKey: "temperature")
                        sanitized.removeValue(forKey: "top_p")
                        AppLog.debug("OpenAI retry without sampling params")
                        return try await makeAPIRequest(
                            endpoint: endpoint,
                            payload: sanitized,
                            allowSamplingFallback: false
                        )
                    }

                    // Smart fallback for GPT-5: switch max_tokens -> max_completion_tokens if needed
                    if httpResponse.statusCode == 400 && allowSamplingFallback,
                        OpenAIProvider.isMaxTokensUnsupportedError(data)
                    {
                        var fixed = payload
                        if let max = fixed.removeValue(forKey: "max_tokens") {
                            fixed["max_completion_tokens"] = max
                        }
                        AppLog.debug("OpenAI retry with max_completion_tokens for GPT-5")
                        return try await makeAPIRequest(
                            endpoint: endpoint,
                            payload: fixed,
                            allowSamplingFallback: false
                        )
                    }

                    if httpResponse.statusCode == 404 || httpResponse.statusCode == 400 {
                        throw AIProviderError.providerSpecificError(
                            "Model not available or request invalid (HTTP \(httpResponse.statusCode)). Check selected model id and account access."
                        )
                    }
                    throw AIProviderError.providerSpecificError("HTTP \(httpResponse.statusCode)")
                }
            } catch {
                lastError = error
                // Network level errors: retry unless out of attempts
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
        // Should not reach here
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
        request.setValue("Bearer \(apiKey ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIProviderError.networkError(URLError(.badServerResponse))
                    }
                    if httpResponse.statusCode != 200 {
                        // Attempt to read error body and also try a non-streaming fallback for a graceful UX
                        recordRequestFailure(httpStatus: httpResponse.statusCode)

                        // Log diagnostic snippet by retrying without streaming
                        var diagRequest = URLRequest(url: request.url!)
                        diagRequest.httpMethod = "POST"
                        request.allHTTPHeaderFields?.forEach { k, v in
                            diagRequest.setValue(v, forHTTPHeaderField: k)
                        }
                        // Remove stream flag if present
                        if var obj = try? JSONSerialization.jsonObject(
                            with: request.httpBody ?? Data()) as? [String: Any]
                        {
                            obj.removeValue(forKey: "stream")
                            diagRequest.httpBody = try? JSONSerialization.data(withJSONObject: obj)
                        } else {
                            diagRequest.httpBody = request.httpBody
                        }

                        if let (d, r) = try? await URLSession.shared.data(for: diagRequest),
                            let hr = r as? HTTPURLResponse
                        {
                            let snippet = String(data: d, encoding: .utf8) ?? "<non-utf8>"
                            AppLog.warn(
                                "OpenAI STREAM HTTP \(hr.statusCode): \(snippet.prefix(500))")

                            // If the diagnostic retry actually succeeded, yield content once as a fallback
                            if 200...299 ~= hr.statusCode,
                                let json = (try? JSONSerialization.jsonObject(with: d))
                                    as? [String: Any],
                                let choices = json["choices"] as? [[String: Any]],
                                let first = choices.first,
                                let message = first["message"] as? [String: Any],
                                let content = message["content"] as? String
                            {
                                continuation.yield(content)
                                continuation.finish()
                                return
                            }

                            // Smart fallback for sampling params in streaming mode
                            if hr.statusCode == 400,
                                OpenAIProvider.isTemperatureUnsupportedErrorData(d)
                            {
                                // Retry once without temperature/top_p in non-streaming mode for a clean message
                                if var obj = try? JSONSerialization.jsonObject(
                                    with: request.httpBody ?? Data()) as? [String: Any]
                                {
                                    obj.removeValue(forKey: "stream")
                                    obj.removeValue(forKey: "temperature")
                                    obj.removeValue(forKey: "top_p")
                                    var retryReq = URLRequest(url: request.url!)
                                    retryReq.httpMethod = "POST"
                                    request.allHTTPHeaderFields?.forEach { k, v in
                                        retryReq.setValue(v, forHTTPHeaderField: k)
                                    }
                                    retryReq.httpBody = try? JSONSerialization.data(
                                        withJSONObject: obj)
                                    if let (rd, rr) = try? await URLSession.shared.data(
                                        for: retryReq),
                                        let rhr = rr as? HTTPURLResponse,
                                        200...299 ~= rhr.statusCode,
                                        let rjson = (try? JSONSerialization.jsonObject(with: rd))
                                            as? [String: Any],
                                        let rchoices = rjson["choices"] as? [[String: Any]],
                                        let rfirst = rchoices.first,
                                        let rmessage = rfirst["message"] as? [String: Any],
                                        let rcontent = rmessage["content"] as? String
                                    {
                                        continuation.yield(rcontent)
                                        continuation.finish()
                                        return
                                    }
                                }
                            }

                            // Smart fallback for max_tokens vs max_completion_tokens for GPT-5
                            if hr.statusCode == 400,
                                OpenAIProvider.isMaxTokensUnsupportedError(d)
                            {
                                if var obj = try? JSONSerialization.jsonObject(
                                    with: request.httpBody ?? Data()) as? [String: Any]
                                {
                                    obj.removeValue(forKey: "stream")
                                    // Rename max_tokens -> max_completion_tokens if present
                                    if let max = obj.removeValue(forKey: "max_tokens") {
                                        obj["max_completion_tokens"] = max
                                    }
                                    var retryReq = URLRequest(url: request.url!)
                                    retryReq.httpMethod = "POST"
                                    request.allHTTPHeaderFields?.forEach { k, v in
                                        retryReq.setValue(v, forHTTPHeaderField: k)
                                    }
                                    retryReq.httpBody = try? JSONSerialization.data(
                                        withJSONObject: obj)
                                    if let (rd, rr) = try? await URLSession.shared.data(
                                        for: retryReq),
                                        let rhr = rr as? HTTPURLResponse,
                                        200...299 ~= rhr.statusCode,
                                        let rjson = (try? JSONSerialization.jsonObject(with: rd))
                                            as? [String: Any],
                                        let rchoices = rjson["choices"] as? [[String: Any]],
                                        let rfirst = rchoices.first,
                                        let rmessage = rfirst["message"] as? [String: Any],
                                        let rcontent = rmessage["content"] as? String
                                    {
                                        continuation.yield(rcontent)
                                        continuation.finish()
                                        return
                                    }
                                }
                            }
                        }

                        throw AIProviderError.providerSpecificError(
                            "Streaming HTTP \(httpResponse.statusCode). Check model id and account access."
                        )
                    }

                    recordRequestSuccess()
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let data = String(line.dropFirst(6))

                            if data == "[DONE]" {
                                break
                            }

                            if let jsonData = data.data(using: .utf8),
                                let json = try? JSONSerialization.jsonObject(with: jsonData)
                                    as? [String: Any],
                                let choices = json["choices"] as? [[String: Any]],
                                let firstChoice = choices.first,
                                let delta = firstChoice["delta"] as? [String: Any],
                                let content = delta["content"] as? String
                            {
                                continuation.yield(content)
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
    ) -> [[String: String]] {
        var messages: [[String: String]] = []

        // System message
        var systemContent =
            "You are a helpful assistant. Answer questions based on provided webpage content."
        if let context = context, !context.isEmpty {
            systemContent += "\n\nWebpage content:\n\(context)"
        }
        messages.append(["role": "system", "content": systemContent])

        // Recent conversation history (last 10 messages)
        let recentHistory = Array(history.suffix(10))
        for message in recentHistory {
            let role = message.role == .user ? "user" : "assistant"
            messages.append(["role": role, "content": message.content])
        }

        // Current query
        messages.append(["role": "user", "content": query])

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

    // MARK: - Model helpers

    private func isNewModelAPI(_ modelId: String) -> Bool {
        return modelId.hasPrefix("gpt-4o") || modelId.hasPrefix("gpt-5")
    }

    // MARK: - Error helpers
    /// Detect OpenAI error when temperature/top_p are not supported by a model
    private static func isTemperatureUnsupportedErrorBody(_ data: Data) -> Bool {
        guard let snippet = String(data: data, encoding: .utf8)?.lowercased() else { return false }
        return snippet.contains("unsupported value") && snippet.contains("temperature")
    }
    private static func isTemperatureUnsupportedErrorData(_ data: Data) -> Bool {
        isTemperatureUnsupportedErrorBody(data)
    }
    /// Detect OpenAI error when `max_tokens` key is not supported
    private static func isMaxTokensUnsupportedError(_ data: Data) -> Bool {
        guard let snippet = String(data: data, encoding: .utf8)?.lowercased() else { return false }
        return snippet.contains("unsupported parameter") && snippet.contains("max_tokens")
    }

    // MARK: - Fallback handling

    private func requestWithModelFallback(
        endpoint: String,
        baseModelId: String,
        basePayload: [String: Any]
    ) async throws -> ([String: Any], String) {
        // Try primary model first
        do {
            let payload = mergedPayload(basePayload, modelId: baseModelId)
            let json = try await makeAPIRequest(endpoint: endpoint, payload: payload)
            return (json, baseModelId)
        } catch {
            // On 400/404 or bad server response, try fallbacks when model is likely unsupported
            if baseModelId.hasPrefix("gpt-5") {
                for fid in ["gpt-4o-mini", "gpt-4o"] {
                    do {
                        let payload = mergedPayload(basePayload, modelId: fid)
                        let json = try await makeAPIRequest(endpoint: endpoint, payload: payload)
                        AppLog.debug("OpenAI fallback -> \(fid) for endpoint \(endpoint)")
                        return (json, fid)
                    } catch {
                        continue
                    }
                }
            }
            throw error
        }
    }

    private func mergedPayload(_ base: [String: Any], modelId: String) -> [String: Any] {
        var payload = base
        payload["model"] = modelId
        return payload
    }

    // MARK: - Settings

    override func getConfigurableSettings() -> [AIProviderSetting] {
        return [
            AIProviderSetting(
                id: "model_selection",
                name: "Model",
                description: "Select the GPT model to use",
                type: .selection(availableModels.map { $0.name }),
                defaultValue: "GPT-5 Mini",
                currentValue: selectedModel?.name ?? "GPT-5 Mini",
                isRequired: true
            ),
            AIProviderSetting(
                id: "temperature",
                name: "Temperature",
                description: "Controls randomness in responses (0.0-2.0)",
                type: .number,
                defaultValue: 0.7,
                currentValue: 0.7,
                isRequired: false
            ),
        ]
    }
}
