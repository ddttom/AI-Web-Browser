import Foundation
import MLX
import MLXLLM
import MLXLMCommon

// MLXRunner included via Web.AI.Runners
// SystemMemoryMonitor included via Web.AI.Utils

/// Gemma AI service for local inference with MLX-Swift
/// Handles model initialization, text generation, and response streaming using MLX models from Hugging Face
class GemmaService {

    // MARK: - Properties

    private let configuration: AIConfiguration
    private let mlxWrapper: MLXWrapper
    private let privacyManager: PrivacyManager
    private let mlxModelService: MLXModelService

    private var isModelLoaded: Bool = false
    // MLX handles model weights and tokenization internally

    // No remote fallbacks - we use MLX models from Hugging Face community only
    // Model download and management handled by MLXModelService

    // MARK: - Initialization

    init(
        configuration: AIConfiguration,
        mlxWrapper: MLXWrapper,
        privacyManager: PrivacyManager,
        mlxModelService: MLXModelService
    ) {
        self.configuration = configuration
        self.mlxWrapper = mlxWrapper
        self.privacyManager = privacyManager
        self.mlxModelService = mlxModelService

        // Memory monitoring removed - was causing unnecessary complexity

        AppLog.debug("GemmaService init: model=\(configuration.modelVariant)")
    }

    // MARK: - Public Interface

    /// Initialize the Gemma model and tokenizer
    func initialize() async throws {
        guard !isModelLoaded else {
            AppLog.debug("Gemma model already loaded")
            return
        }

        do {
            // Initialize MLX model service and ensure model is available
            try await mlxModelService.initializeAI()

            guard await mlxModelService.isAIReady() else {
                throw GemmaError.modelNotAvailable(
                    "MLX model initialization did not complete successfully")
            }

            isModelLoaded = true
            AppLog.debug("MLX Gemma model loaded successfully")

        } catch {
            AppLog.error("Gemma init failed: \(error.localizedDescription)")
            throw GemmaError.initializationFailed(error.localizedDescription)
        }
    }

    /// Generate a response for the given query and context
    func generateResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage]
    ) async throws -> AIResponse {

        guard isModelLoaded else {
            throw GemmaError.modelNotLoaded
        }

        // Memory pressure checks removed - were causing unnecessary complexity

        let responseBuilder = AIResponseBuilder()
        let _ = Date()  // Track timing but not used in current implementation

        do {
            // Step 1: Prepare the prompt
            let _ = responseBuilder.addProcessingStep(
                ProcessingStep(
                    name: "prompt_preparation",
                    duration: 0.1,
                    description: "Preparing input prompt with context"
                ))

            let prompt = try buildPrompt(
                query: query,
                context: context,
                conversationHistory: conversationHistory
            )

            if context != nil {
                let _ = responseBuilder.setContextUsed(true)
            }

            // MLX handles tokenization internally - no separate tokenizer needed

            // Use MLX-Swift for local inference
            let _ = responseBuilder.addProcessingStep(
                ProcessingStep(
                    name: "mlx_inference", duration: 0, description: "Running MLX-Swift inference"))

            do {
                // Use consistent prompt-based approach (conversation context already included in prompt)
                let generatedText = try await SimplifiedMLXRunner.shared.generateWithPrompt(
                    prompt: prompt, modelId: "gemma3_2B_4bit")
                let cleaned = postProcessResponse(generatedText)
                // Estimate token count for metrics (MLX handles tokenization internally)
                let estimatedTokens = Int(Double(generatedText.count) / 3.5)
                mlxWrapper.updateInferenceMetrics(tokensGenerated: estimatedTokens)
                return responseBuilder.setText(cleaned).setMemoryUsage(Int(mlxWrapper.memoryUsage))
                    .build()
            } catch {
                AppLog.error("MLX inference failed: \(error.localizedDescription)")
                throw GemmaError.inferenceError(
                    "MLX inference failed: \(error.localizedDescription)")
            }

            // All inference handled above by MLXRunner

        } catch {
            AppLog.error("Gemma response generation failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Generate a streaming response with real-time token updates
    func generateStreamingResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage]
    ) async throws -> AsyncThrowingStream<String, Error> {

        guard isModelLoaded else {
            throw GemmaError.modelNotLoaded
        }

        // Memory pressure checks removed - were causing unnecessary complexity

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Prepare prompt
                    let prompt = try buildPrompt(
                        query: query,
                        context: context,
                        conversationHistory: conversationHistory
                    )

                    // MLX handles tokenization internally

                    // Use MLXRunner for streaming with pre-built prompt that includes conversation context
                    let textStream = await SimplifiedMLXRunner.shared.generateStreamWithPrompt(
                        prompt: prompt, modelId: "gemma3_2B_4bit")

                    var hasYieldedContent = false
                    var accumulatedResponse = ""

                    do {
                        for try await textChunk in textStream {
                            // PRESERVE LINE BREAKS: Don't post-process individual chunks during streaming
                            // as this can strip U+000A characters. Only clean obvious control tokens.
                            var cleanedChunk = textChunk

                            // Only remove MLX-specific control tokens, preserve all whitespace and line breaks
                            cleanedChunk = cleanedChunk.replacingOccurrences(
                                of: "<|endoftext|>", with: "")
                            cleanedChunk = cleanedChunk.replacingOccurrences(
                                of: "<start_of_turn>", with: "")
                            cleanedChunk = cleanedChunk.replacingOccurrences(
                                of: "<end_of_turn>", with: "")
                            cleanedChunk = cleanedChunk.replacingOccurrences(of: "<bos>", with: "")
                            cleanedChunk = cleanedChunk.replacingOccurrences(of: "<eos>", with: "")

                            // Always yield the chunk even if it's just whitespace/line breaks
                            accumulatedResponse += cleanedChunk
                            hasYieldedContent = true
                            continuation.yield(cleanedChunk)
                        }

                        // If no content was streamed, provide a helpful fallback
                        if !hasYieldedContent {
                            AppLog.debug(
                                "No content streamed; providing fallback (len=\(accumulatedResponse.count))"
                            )
                            let fallbackResponse =
                                "I'm ready to help you with questions about the current webpage content."
                            continuation.yield(fallbackResponse)
                        }

                        continuation.finish()
                        NSLog(
                            "✅ Streaming completed successfully: \(accumulatedResponse.count) characters"
                        )

                    } catch {
                        AppLog.error("Gemma streaming error: \(error.localizedDescription)")

                        // Provide error recovery with helpful message
                        if !hasYieldedContent {
                            let recoveryMessage: String
                            if error.localizedDescription.contains("memory") {
                                recoveryMessage =
                                    "Memory constraints prevented AI response. Try a shorter query or restart the app."
                            } else if error.localizedDescription.contains("timeout") {
                                recoveryMessage =
                                    "AI response timed out. Please try a more specific question."
                            } else {
                                recoveryMessage =
                                    "AI service temporarily unavailable. Please try again in a moment."
                            }
                            continuation.yield(recoveryMessage)
                        }

                        continuation.finish()
                    }

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Summarize a conversation
    func summarizeConversation(_ messages: [ConversationMessage]) async throws -> String {
        let conversationText = messages.map { "\($0.role.description): \($0.content)" }.joined(
            separator: "\n")

        let summaryPrompt = """
            Summarize the following conversation in 2-3 sentences, focusing on the main topics and outcomes:

            \(conversationText)

            Summary:
            """

        let response = try await generateResponse(
            query: summaryPrompt,
            context: nil,
            conversationHistory: []
        )

        return response.text
    }

    // MARK: - Private Methods

    private func buildPrompt(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage]
    ) throws -> String {

        // VALIDATION: Ensure conversation history is clean and valid
        let validatedHistory = conversationHistory.filter { message in
            // Remove empty or corrupted messages
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let isValid = !content.isEmpty && content.count > 2

            if !isValid {
                if AppLog.isVerboseEnabled {
                    AppLog.debug("Filtered invalid message: '\(message.content.prefix(50))…'")
                }
            }

            return isValid
        }

        if AppLog.isVerboseEnabled {
            AppLog.debug(
                "Conversation validation: \(conversationHistory.count) → \(validatedHistory.count)")
        }

        // ENHANCED: Build proper multi-turn conversation prompt with context placed strategically
        var promptParts: [String] = []

        // System prompt as first user turn - simplified and clearer
        promptParts.append("<start_of_turn>user")
        promptParts.append(
            "You are a helpful assistant. Answer questions based on provided webpage content.")
        promptParts.append("<end_of_turn>")

        // Assistant acknowledges
        promptParts.append("<start_of_turn>model")
        promptParts.append("I'll help answer questions using the webpage content.")
        promptParts.append("<end_of_turn>")

        // Add recent conversation history for continuity (increased for better follow-up context)
        let recentHistory = Array(validatedHistory.suffix(8))  // Last 4 exchanges for better continuity
        for message in recentHistory {
            if message.role == .user {
                promptParts.append("<start_of_turn>user")
                promptParts.append(message.content)
                promptParts.append("<end_of_turn>")
            } else if message.role == .assistant {
                promptParts.append("<start_of_turn>model")
                promptParts.append(message.content)
                promptParts.append("<end_of_turn>")
            }
        }

        // CRITICAL FIX: Place context RIGHT BEFORE the current question
        promptParts.append("<start_of_turn>user")

        if let context = context, !context.isEmpty {
            let cleanContext = String(context.prefix(6000))
                .replacingOccurrences(of: "\n\n+", with: "\n", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Structure: Context first, then question - makes it clear what to reference
            promptParts.append(
                "WEBPAGE CONTENT:\n\(cleanContext)\n\n---\n\nBased on the above webpage content, please answer: \(query)"
            )
        } else {
            promptParts.append(query)
        }

        promptParts.append("<end_of_turn>")

        // Assistant response start
        promptParts.append("<start_of_turn>model")

        let fullPrompt = promptParts.joined(separator: "\n")

        if AppLog.isVerboseEnabled {
            AppLog.debug("Built Gemma prompt (len=\(fullPrompt.count)) context=\(context != nil)")
        }
        if context != nil {
            if AppLog.isVerboseEnabled {
                AppLog.debug("Context preview: \(String(context!.prefix(200)))…")
            }
        }
        if AppLog.isVerboseEnabled {
            AppLog.debug("Prompt tail: \(String(fullPrompt.suffix(500)))")
        }
        if AppLog.isVerboseEnabled {
            AppLog.debug("FULL PROMPT (truncated): \(String(fullPrompt.prefix(2000)))")
        }

        return fullPrompt
    }

    /// Reset conversation state to prevent KV cache issues
    func resetConversation() async {
        // Reset the MLX runner's conversation state
        await SimplifiedMLXRunner.shared.resetConversation()
        AppLog.debug("GemmaService conversation reset completed")
    }

    // Memory pressure handling removed - was overcomplicating the system

    // All inference now handled by MLXRunner using MLX models from Hugging Face

    /// Post-processes raw output from the model to remove artifacts.
    ///
    /// - Parameters:
    ///   - text: Raw text emitted by the model.
    ///   - trimWhitespace: When true (default) leading/trailing whitespace and newline characters are trimmed. For streaming output we set this to **false** so that legitimate leading spaces between tokens are preserved.
    ///                     This prevents issues where streamed tokens like "Hello" "world" are concatenated into "Helloworld" when whitespace is stripped on every chunk.
    private func postProcessResponse(_ text: String, trimWhitespace: Bool = true) -> String {
        // Clean up the response
        var cleaned = text

        // Remove common artifacts and Gemma-specific tokens
        cleaned = cleaned.replacingOccurrences(of: "<|endoftext|>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<|user|>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<|assistant|>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<start_of_turn>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<end_of_turn>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<bos>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<eos>", with: "")

        // Stop generation at repetitive patterns
        if cleaned.contains("I am sorry, I do not have access") {
            // Find first occurrence and truncate there
            if let range = cleaned.range(of: "I am sorry, I do not have access") {
                let beforeRepetition = cleaned[..<range.lowerBound]
                if !beforeRepetition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    cleaned = String(beforeRepetition)
                } else {
                    // If the response starts with repetition, give a simple answer
                    cleaned = "I can help you with questions about the current webpage content."
                }
            }
        }

        // Remove excessive repetition by looking for identical sentences
        let sentences = cleaned.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        var uniqueSentences: [String] = []
        var seenSentences = Set<String>()

        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !seenSentences.contains(trimmed) {
                uniqueSentences.append(sentence)
                seenSentences.insert(trimmed)
            }
        }

        if uniqueSentences.count < sentences.count {
            // Preserve natural line breaks between sentences to improve readability and markdown rendering
            cleaned = uniqueSentences.joined(separator: ".\n")
        }

        // NEW: Collapse repeated adjacent words (e.g. "it it", "you you") that sometimes
        // appear in streamed output when the tokenizer emits duplicated tokens. This is a
        // lightweight regex-based pass that keeps the first occurrence and removes the rest.
        // It is case-insensitive and works across multiple repetitions in a row.
        do {
            let pattern = "\\b(\\w+)(?:\\s+\\1)+\\b"
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: cleaned.utf16.count)
            cleaned = regex.stringByReplacingMatches(
                in: cleaned, options: [], range: range, withTemplate: "$1")
        } catch {
            AppLog.warn("Regex error collapsing repeated words: \(error.localizedDescription)")
        }

        // NEW: Collapse repeated adjacent words that appear **without** intervening whitespace, often a byproduct
        // of tokenization artifacts when leading spaces are stripped from successive tokens. For example,
        // "Itit seems" should be reduced to "It seems". We perform a second regex pass that catches the
        // pattern of the *exact* same word appearing at least twice in immediate succession.
        do {
            let patternNoSpace = "\\b(\\w{1,20}?)\\1+\\b"
            let regexNoSpace = try NSRegularExpression(
                pattern: patternNoSpace, options: [.caseInsensitive])
            let rangeNoSpace = NSRange(location: 0, length: cleaned.utf16.count)
            // Replace the full match with a single captured word followed by a space so that we don't merge
            // the next word when there originally should have been whitespace.
            cleaned = regexNoSpace.stringByReplacingMatches(
                in: cleaned, options: [], range: rangeNoSpace, withTemplate: "$1 ")
        } catch {
            AppLog.warn("Regex error collapsing adjacent words: \(error.localizedDescription)")
        }

        // NEW: Ensure common Markdown block tokens start on their own line so that downstream renderers
        // (ChatBubbleView, TLDRCard, etc.) don’t mis-interpret them as inline emphasis and break.
        cleaned =
            cleaned
            // Bullets immediately following a colon ("We can:*" → "We can:\n* ")
            .replacingOccurrences(of: "(?<=:)\\s*\\*", with: "\n* ", options: .regularExpression)
            // Generic bullets/ordered list markers that are missing a leading newline
            .replacingOccurrences(
                of: "(?<![\\n])([*+-]\\s+)", with: "\n$1", options: .regularExpression
            )
            // Headings (e.g. "# Heading")
            .replacingOccurrences(
                of: "(?<![\\n])(#+\\s+)", with: "\n$1", options: .regularExpression
            )
            // Code fences (```)
            .replacingOccurrences(of: "(?<![\\n])(```)", with: "\n$1", options: .regularExpression)

        // Dynamic response length based on memory availability
        let memoryPressure = ProcessInfo.processInfo.thermalState
        let maxResponseLength: Int

        switch memoryPressure {
        case .critical:
            maxResponseLength = 1000  // Shorter responses under critical memory pressure
        case .serious:
            maxResponseLength = 2500  // Medium responses under serious memory pressure
        case .fair:
            maxResponseLength = 4000  // Longer responses when memory is fair
        case .nominal:
            maxResponseLength = 6000  // Full responses when memory is good
        @unknown default:
            maxResponseLength = 2500  // Safe default
        }

        // Only limit if significantly over the threshold (25% buffer)
        if cleaned.count > Int(Double(maxResponseLength) * 1.25) {
            // Find a good stopping point near the limit
            if let range = cleaned.range(
                of: ".",
                range: cleaned
                    .startIndex..<cleaned.index(
                        cleaned.startIndex, offsetBy: min(maxResponseLength, cleaned.count)))
            {
                cleaned = String(cleaned[..<range.upperBound])
            } else {
                cleaned = String(cleaned.prefix(maxResponseLength)) + "..."
            }
            if AppLog.isVerboseEnabled {
                AppLog.debug("Response truncated to \(cleaned.count) (\(memoryPressure))")
            }
        }

        // Optionally trim whitespace (disabled for streaming so that spaces between tokens are preserved)
        if trimWhitespace {
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned
    }

    // MARK: - TLDR Specific Cleanup

    /// Additional cleanup pass used by the TL;DR pipeline to salvage a summary when the
    /// model produces heavy phrase-level repetition. It repeatedly collapses any 3-6 word
    /// chunk that appears two or more times in a row (case-insensitive) until no such
    /// patterns remain. This sits on top of `postProcessResponse`.
    /// - Parameter text: The raw summary to clean.
    /// - Returns: A cleaned version with collapsed repetitions.
    func postProcessForTLDR(_ text: String) -> String {
        var cleaned = text

        // First, reuse postProcessResponse to remove simpler artifacts while preserving
        // whitespace between tokens so that phrase boundaries remain intact.
        cleaned = postProcessResponse(cleaned, trimWhitespace: false)

        // Regex to capture a 3-6 word phrase that repeats consecutively (case-insensitive).
        let phrasePattern = "(\\b(?:[A-Za-z0-9]+\\s+){2,5}[A-Za-z0-9]+\\b)(?:\\s+\\1)+"

        do {
            let regex = try NSRegularExpression(pattern: phrasePattern, options: [.caseInsensitive])
            var previous: String
            repeat {
                previous = cleaned
                let range = NSRange(location: 0, length: cleaned.utf16.count)
                cleaned = regex.stringByReplacingMatches(
                    in: cleaned, options: [], range: range, withTemplate: "$1")
            } while previous != cleaned  // Iterate until no more replacements
        } catch {
            AppLog.warn("Regex error collapsing repeated phrases: \(error.localizedDescription)")
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Generate a response from a RAW prompt without adding the conversation chat template.
    /// This is useful for utility features such as TL;DR summaries where the entire
    /// instruction is contained in the prompt itself and we do **not** want the
    /// additional <start_of_turn> metadata or prior conversation context.
    /// - Parameter prompt: The raw prompt to send to the model.
    /// - Returns: The model’s cleaned response string.
    func generateRawResponse(prompt: String) async throws -> String {
        guard isModelLoaded else {
            throw GemmaError.modelNotLoaded
        }

        do {
            let generated = try await SimplifiedMLXRunner.shared.generateWithPrompt(
                prompt: prompt, modelId: "gemma3_2B_4bit")
            // Preserve leading spaces between tokens so that duplicate-word regex works correctly
            let cleaned = postProcessResponse(generated, trimWhitespace: false)
            // Finally, trim outer whitespace/newlines to keep the output tidy for display
            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            AppLog.error("Gemma raw generation failed: \(error.localizedDescription)")
            throw GemmaError.inferenceError("MLX inference failed: \(error.localizedDescription)")
        }
    }

    // Context reference processing will be added in Phase 11
}

// MARK: - MLX Integration Notes

/// MLX-Swift handles tokenization internally through its model context
/// No separate tokenizer class is needed as MLX provides this functionality

// MARK: - Errors

enum GemmaError: LocalizedError {
    case modelNotAvailable(String)
    case modelNotLoaded
    case initializationFailed(String)
    case mlxNotAvailable
    case promptTooLong(String)
    case inferenceError(String)

    var errorDescription: String? {
        switch self {
        case .modelNotAvailable(let message):
            return "Model Not Available: \(message)"
        case .modelNotLoaded:
            return "Model not loaded - call initialize() first"
        case .initializationFailed(let message):
            return "Initialization Failed: \(message)"
        case .mlxNotAvailable:
            return "MLX runtime not available"
        case .promptTooLong(let message):
            return "Prompt Too Long: \(message)"
        case .inferenceError(let message):
            return "Inference Error: \(message)"
        }
    }
}
