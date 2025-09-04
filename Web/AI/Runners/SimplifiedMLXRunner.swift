import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// Simplified MLX-based LLM runner following WWDC 2025 patterns
/// Uses basic string-based model loading without complex configurations
/// AI THREADING FIX: Removed @MainActor to allow background processing
final class SimplifiedMLXRunner: ObservableObject {
    static let shared = SimplifiedMLXRunner()

    // AI THREADING FIX: Thread-safe published properties with main actor updates
    @Published var isLoading = false
    @Published var loadProgress: Float = 0.0

    private var modelContainer: ModelContainer?
    private var currentModelId: String?
    
    /// Check if a model is currently loaded
    var isModelLoaded: Bool {
        return modelContainer != nil
    }

    // Use ModelRegistry for predefined configurations
    private let defaultModelId = "gemma3_2B_4bit"

    // Background processing queue for AI inference
    private let aiProcessingQueue = DispatchQueue(label: "ai.processing", qos: .userInitiated)
    private let modelLoadingQueue = DispatchQueue(label: "ai.model.loading", qos: .userInitiated)

    private init() {
        // SimplifiedMLXRunner initialized
    }

    /// Ensure model is loaded using ModelRegistry ID
    /// AI THREADING FIX: Runs on background thread to prevent UI blocking
    func ensureLoaded(modelId: String = "gemma3_2B_4bit") async throws {
        AppLog.debug("🚀 [MLX RUNNER] === ensureLoaded() called ===")
        AppLog.debug("🚀 [MLX RUNNER] Requested model ID: \(modelId)")
        AppLog.debug("🚀 [MLX RUNNER] Current model ID: \(currentModelId ?? "nil")")
        AppLog.debug("🚀 [MLX RUNNER] Model container loaded: \(modelContainer != nil)")
        
        // If already loaded with same model, return immediately
        if modelContainer != nil && currentModelId == modelId {
            AppLog.debug("🚀 [MLX RUNNER] ✅ Model already loaded - no action needed")
            return
        }

        // AI THREADING FIX: Update UI state on main thread
        await MainActor.run {
            isLoading = true
            loadProgress = 0.0
        }

        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        AppLog.debug("🚀 [MLX RUNNER] Starting model load process for: \(modelId)")

        do {
            // Use MLX-Swift ModelRegistry for predefined models
            let modelConfig: ModelConfiguration
            AppLog.debug("🚀 [MLX RUNNER] Determining model configuration for: \(modelId)")
            
            switch modelId {
            case "llama3_2_1B_4bit":
                AppLog.debug("🚀 [MLX RUNNER] Using registry config for llama3_2_1B_4bit")
                modelConfig = LLMRegistry.llama3_2_1B_4bit
            case "llama3_2_3B_4bit":
                AppLog.debug("🚀 [MLX RUNNER] Using registry config for llama3_2_3B_4bit")
                modelConfig = LLMRegistry.llama3_2_3B_4bit
            case "gemma3_2B_4bit":
                AppLog.debug("🚀 [MLX RUNNER] Using hardcoded config for gemma3_2B_4bit")
                modelConfig = ModelConfiguration(id: "mlx-community/gemma-2-2b-it-4bit")
                AppLog.debug("🚀 [MLX RUNNER] Model config ID: mlx-community/gemma-2-2b-it-4bit")
            case "gemma3_9B_4bit":
                AppLog.debug("🚀 [MLX RUNNER] Using hardcoded config for gemma3_9B_4bit")
                modelConfig = ModelConfiguration(id: "mlx-community/gemma-2-9b-it-4bit")
            case "mlx-community/gemma-2-2b-it-4bit":
                AppLog.debug("🚀 [MLX RUNNER] Using direct Hugging Face repo format for gemma-2-2b-it-4bit")
                modelConfig = ModelConfiguration(id: modelId)
            case "mlx-community/gemma-2-9b-it-4bit":
                AppLog.debug("🚀 [MLX RUNNER] Using direct Hugging Face repo format for gemma-2-9b-it-4bit")
                modelConfig = ModelConfiguration(id: modelId)
            case "mlx-community/Llama-3.2-1B-Instruct-4bit":
                AppLog.debug("🚀 [MLX RUNNER] Using direct Hugging Face repo format for Llama-3.2-1B-Instruct-4bit")
                modelConfig = ModelConfiguration(id: modelId)
            case "mlx-community/Llama-3.2-3B-Instruct-4bit":
                AppLog.debug("🚀 [MLX RUNNER] Using direct Hugging Face repo format for Llama-3.2-3B-Instruct-4bit")
                modelConfig = ModelConfiguration(id: modelId)
            default:
                AppLog.debug("🚀 [MLX RUNNER] Using fallback custom configuration for: \(modelId)")
                modelConfig = ModelConfiguration(id: modelId)
            }
            
            AppLog.debug("🚀 [MLX RUNNER] Final model configuration ID: \(modelConfig.id)")

            // Enhanced error handling with detailed logging
            AppLog.debug("🚀 [MLX RUNNER] Starting LLMModelFactory.loadContainer() call")
            AppLog.debug("🚀 [MLX RUNNER] Configuration ID: \(modelConfig.id)")

            // AI THREADING FIX: Model loading with proper thread management and enhanced error handling
            let model = try await LLMModelFactory.shared.loadContainer(
                configuration: modelConfig
            ) { progress in
                // AI THREADING FIX: Progress updates on main thread
                Task { @MainActor in
                    self.loadProgress = Float(progress.fractionCompleted)
                    if Int(progress.fractionCompleted * 100) % 10 == 0 {  // Only log every 10%
                        AppLog.debug("🚀 [MLX RUNNER] Model loading progress: \(Int(progress.fractionCompleted * 100))%")
                    }
                }
            }

            self.modelContainer = model
            self.currentModelId = modelId

            // AI THREADING FIX: Final progress update on main thread
            await MainActor.run {
                self.loadProgress = 1.0
            }

            AppLog.debug("🚀 [MLX RUNNER] ✅ Model loaded successfully: \(modelId)")
            AppLog.debug("🚀 [MLX RUNNER] Model container created and stored")

        } catch {
            AppLog.error("🚀 [MLX RUNNER] ❌ Failed to load MLX model: \(error.localizedDescription)")
            AppLog.error("🚀 [MLX RUNNER] Requested model ID: \(modelId)")
            AppLog.error("🚀 [MLX RUNNER] Error type: \(type(of: error))")
            
            // Enhanced error reporting with specific guidance
            let enhancedError: Error
            let errorDescription = error.localizedDescription.lowercased()
            
            if errorDescription.contains("couldn't be moved") || errorDescription.contains("file not found") {
                AppLog.error("🚀 [MLX RUNNER] 🔍 ERROR CATEGORY: File/Download Issue")
                enhancedError = SimplifiedMLXError.downloadCorrupted(
                    "Model download was interrupted or files are missing. The cache will be cleaned up automatically on next attempt. "
                        + "Please check your network connection and try again."
                )
            } else if errorDescription.contains("config.json") {
                AppLog.error("🚀 [MLX RUNNER] 🔍 ERROR CATEGORY: Configuration Missing")
                enhancedError = SimplifiedMLXError.configurationMissing(
                    "Model configuration files are missing or corrupted. "
                        + "The app will attempt to re-download the model automatically."
                )
            } else if errorDescription.contains("tokenizer") {
                AppLog.error("🚀 [MLX RUNNER] 🔍 ERROR CATEGORY: Tokenizer Corruption")
                enhancedError = SimplifiedMLXError.tokenizerCorrupted(
                    "Model tokenizer files are corrupted. "
                        + "This usually happens due to interrupted downloads. The cache will be cleaned up automatically."
                )
            } else if errorDescription.contains("model") && errorDescription.contains("not") && errorDescription.contains("found") {
                AppLog.error("🚀 [MLX RUNNER] 🔍 ERROR CATEGORY: Model Not Found")
                enhancedError = SimplifiedMLXError.configurationMissing(
                    "Model files not found in expected location. This suggests a mismatch between manual download location and app expectations."
                )
            } else {
                AppLog.error("🚀 [MLX RUNNER] 🔍 ERROR CATEGORY: Other/Unknown")
                enhancedError = SimplifiedMLXError.generationFailed(error.localizedDescription)
            }

            throw enhancedError
        }
    }

    /// Generate text with simple prompt
    /// AI THREADING FIX: Runs inference on background thread to prevent UI blocking
    func generateWithPrompt(prompt: String, modelId: String = "gemma3_2B_4bit") async throws
        -> String
    {
        try await ensureLoaded(modelId: modelId)

        guard let context = modelContainer else {
            throw SimplifiedMLXError.modelNotLoaded
        }

        // AI THREADING FIX: Run MLX inference on background thread
        // Use Task.detached to avoid Sendable requirements and run on background thread
        return try await Task.detached(priority: .userInitiated) {
            try await self.performMLXInference(context: context, prompt: prompt)
        }.value
    }

    /// Performs the actual MLX inference on background thread
    /// AI THREADING FIX: Separated inference logic for background processing
    private func performMLXInference(context: ModelContainer, prompt: String) async throws -> String
    {
        // Generating with MLX

        do {
            // Use MLX-Swift ModelContainer.perform API with ModelContext
            let result = try await context.perform { modelContext in
                NSLog("🔍 MLX DEBUG: Preparing input for prompt (\(prompt.count) chars)")
                NSLog("🔍 MLX DEBUG: Prompt preview: '\(prompt.prefix(200))...'")
                let input = try await modelContext.processor.prepare(input: .init(prompt: prompt))
                NSLog("🔍 MLX DEBUG: Input prepared successfully")
                let parameters = GenerateParameters(
                    maxTokens: 512,
                    temperature: 0.7,
                    topP: 0.9
                )

                var allTokens: [Int] = []

                var previousTokenCount = 0
                var stagnantCount = 0
                var lastTokenSequence: [Int] = []
                let repetitionDetectionWindow = 10

                NSLog(
                    "🔍 MLX DEBUG: Starting generation with maxTokens=\(parameters.maxTokens ?? 0), temp=\(parameters.temperature)"
                )
                let _ = try MLXLMCommon.generate(
                    input: input,
                    parameters: parameters,
                    context: modelContext
                ) { tokens in
                    if allTokens.isEmpty {
                        NSLog("🔍 MLX DEBUG: First token callback - \(tokens.count) tokens")
                    }
                    // Removed excessive logging for cleaner output

                    // Store the complete token array - MLX gives us all tokens accumulated so far
                    allTokens = tokens

                    // IMPROVED: Stop if no progress is being made (token count not increasing)
                    if tokens.count == previousTokenCount {
                        stagnantCount += 1
                        if stagnantCount >= 8 {  // Increased from 5 to 8 for more patient generation
                            NSLog("🛑 Stopping: no token progress for 8 iterations")
                            return .stop
                        }
                    } else {
                        stagnantCount = 0
                        previousTokenCount = tokens.count
                    }

                    // Stop if we have enough tokens or find EOS
                    if tokens.count >= 512 {
                        NSLog("🛑 Stopping: reached max tokens (\(tokens.count))")
                        return .stop
                    }

                    // IMPROVED: Enhanced EOS token detection with more tokens
                    let eosTokens: Set<Int> = [2, 1, 0, 128001, 128008, 128009]  // Include more common EOS tokens
                    if let lastToken = tokens.last, eosTokens.contains(lastToken) {
                        NSLog("🛑 Stopping: found EOS token \(lastToken)")
                        return .stop
                    }

                    // NEW: Detect token sequence repetition to prevent infinite loops
                    if tokens.count >= repetitionDetectionWindow {
                        let recentTokens = Array(tokens.suffix(repetitionDetectionWindow))
                        if recentTokens == lastTokenSequence {
                            NSLog("🛑 Stopping: detected repeated token sequence \(recentTokens)")
                            return .stop
                        }
                        lastTokenSequence = recentTokens
                    }

                    // NEW: Detect if the same token is being repeated excessively
                    if tokens.count >= 5 {
                        let lastFiveTokens = Array(tokens.suffix(5))
                        let uniqueTokens = Set(lastFiveTokens)
                        if uniqueTokens.count == 1 {
                            NSLog(
                                "🛑 Stopping: same token repeated 5 times: \(uniqueTokens.first ?? -1)"
                            )
                            return .stop
                        }
                    }

                    return .more
                }

                NSLog("🔤 Decoding \(allTokens.count) total tokens...")
                let fullResponse = modelContext.tokenizer.decode(tokens: allTokens)
                NSLog("📝 Final decoded response: \(fullResponse.count) characters")
                if fullResponse.isEmpty {
                    NSLog(
                        "⚠️ WARNING: MLX tokenizer returned empty response despite \(allTokens.count) tokens"
                    )
                    NSLog("🔍 MLX DEBUG: Sample tokens: \(Array(allTokens.prefix(10)))")
                } else {
                    NSLog(
                        "🔍 MLX DEBUG: Successfully decoded \(allTokens.count) tokens to \(fullResponse.count) characters"
                    )
                }

                return fullResponse
            }

            // MLX response generated
            return result
        } catch {
            NSLog("❌ MLX generation failed: \(error)")
            throw SimplifiedMLXError.generationFailed(error.localizedDescription)
        }
    }

    /// Generate streaming response
    /// AI THREADING FIX: Runs streaming inference on background thread
    func generateStreamWithPrompt(prompt: String, modelId: String = "gemma3_2B_4bit")
        -> AsyncThrowingStream<String, Error>
    {
        AsyncThrowingStream<String, Error> { continuation in
            // AI THREADING FIX: Run streaming on background thread
            aiProcessingQueue.async {
                Task {
                    do {
                        try await self.ensureLoaded(modelId: modelId)

                        guard let container = self.modelContainer else {
                            continuation.finish(throwing: SimplifiedMLXError.modelNotLoaded)
                            return
                        }

                        // Starting MLX streaming

                        try await container.perform { modelContext in
                            NSLog(
                                "🔍 MLX STREAMING DEBUG: Preparing input for prompt (\(prompt.count) chars)"
                            )
                            let input = try await modelContext.processor.prepare(
                                input: .init(prompt: prompt))
                            NSLog("🔍 MLX STREAMING DEBUG: Input prepared successfully")
                            let parameters = GenerateParameters(
                                maxTokens: 512,
                                temperature: 0.7,
                                topP: 0.9
                            )

                            // Track the length of text we've already sent to avoid duplication
                            var sentTextLength = 0
                            let maxTokens = 512
                            var previousTokenCount = 0
                            var stagnantCount = 0
                            var lastTokenSequence: [Int] = []
                            let repetitionDetectionWindow = 10

                            NSLog("🔍 MLX STREAMING DEBUG: Starting generation...")
                            let _ = try MLXLMCommon.generate(
                                input: input,
                                parameters: parameters,
                                context: modelContext
                            ) { tokens in
                                // Enhanced debug logging for TLDR streaming issues
                                if previousTokenCount < 5 {
                                    NSLog(
                                        "🔍 MLX Streaming iteration \(previousTokenCount + 1): \(tokens.count) tokens, last token: \(tokens.last?.description ?? "none")"
                                    )
                                    if tokens.count > 0 {
                                        let decodedSample = modelContext.tokenizer.decode(
                                            tokens: Array(tokens.prefix(min(10, tokens.count))))
                                        NSLog("🔍 MLX Streaming sample decode: '\(decodedSample)'")
                                    }
                                }

                                // IMPROVED: Stop if no progress is being made (token count not increasing)
                                // Increased threshold for TL;DR tasks that might need more "thinking" time
                                if tokens.count == previousTokenCount {
                                    stagnantCount += 1
                                    if stagnantCount >= 15 {  // Increased from 5 to 15 for better TL;DR generation
                                        NSLog(
                                            "🛑 Stopping streaming: no token progress for 15 iterations"
                                        )
                                        return .stop
                                    }
                                } else {
                                    stagnantCount = 0
                                    previousTokenCount = tokens.count
                                }

                                // Stop if we've reached the maximum token limit
                                if tokens.count >= maxTokens {
                                    NSLog(
                                        "🛑 Stopping streaming: reached max tokens (\(tokens.count))"
                                    )
                                    return .stop
                                }

                                // IMPROVED: Enhanced EOS token detection with more tokens
                                let eosTokens: Set<Int> = [2, 1, 0, 128001, 128008, 128009]  // Include more common EOS tokens
                                if let lastToken = tokens.last, eosTokens.contains(lastToken) {
                                    NSLog("🛑 Stopping streaming: found EOS token \(lastToken)")
                                    return .stop
                                }

                                // NEW: Detect token sequence repetition to prevent infinite loops
                                if tokens.count >= repetitionDetectionWindow {
                                    let recentTokens = Array(
                                        tokens.suffix(repetitionDetectionWindow))
                                    if recentTokens == lastTokenSequence {
                                        NSLog(
                                            "🛑 Stopping streaming: detected repeated token sequence \(recentTokens)"
                                        )
                                        return .stop
                                    }
                                    lastTokenSequence = recentTokens
                                }

                                // NEW: Detect if the same token is being repeated excessively
                                if tokens.count >= 5 {
                                    let lastFiveTokens = Array(tokens.suffix(5))
                                    let uniqueTokens = Set(lastFiveTokens)
                                    if uniqueTokens.count == 1 {
                                        NSLog(
                                            "🛑 Stopping streaming: same token repeated 5 times: \(uniqueTokens.first ?? -1)"
                                        )
                                        return .stop
                                    }
                                }

                                // Only process if we have new tokens
                                if tokens.count > 0 {
                                    // FIXED: Decode the complete token array for proper Unicode/word boundaries
                                    let fullText = modelContext.tokenizer.decode(tokens: tokens)

                                    // NEW: Check for obvious repetitive text patterns in the decoded output
                                    if fullText.count > sentTextLength {
                                        let newText = String(fullText.dropFirst(sentTextLength))

                                        // Simple repetition check for new text
                                        if newText.count > 20 {
                                            let words = newText.components(
                                                separatedBy: .whitespacesAndNewlines)
                                            if words.count >= 4 {
                                                let lastFourWords = Array(words.suffix(4))
                                                let uniqueWords = Set(lastFourWords)
                                                if uniqueWords.count <= 2 && words.count > 6 {
                                                    NSLog(
                                                        "🛑 Stopping streaming: detected repetitive text pattern"
                                                    )
                                                    return .stop
                                                }
                                            }
                                        }

                                        NSLog(
                                            "📝 MLX Streaming yielding: '\(newText.prefix(50))...' (\(newText.count) chars)"
                                        )

                                        if !newText.isEmpty {
                                            continuation.yield(newText)
                                            sentTextLength = fullText.count
                                        } else {
                                            NSLog(
                                                "⚠️ MLX Streaming: newText is empty despite tokens")
                                            NSLog(
                                                "🔍 MLX Streaming DEBUG: fullText='\(fullText)', sentTextLength=\(sentTextLength)"
                                            )
                                        }
                                    }
                                }

                                return .more
                            }
                        }

                        continuation.finish()
                        // Reduced logging for cleaner output

                    } catch {
                        NSLog("❌ MLX streaming failed: \(error)")
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    /// Reset conversation state
    /// AI THREADING FIX: Runs on background thread to prevent UI blocking
    func resetConversation() async {
        // FIXED: Implement proper conversation state reset
        // For MLX, we need to clear the model's internal state by recreating the model container
        guard let currentModelId = currentModelId else {
            // MLX conversation reset: no model loaded
            return
        }

        // AI THREADING FIX: Run reset on main actor to avoid Sendable issues
        await MainActor.run {
            // MLX conversation reset: clearing model state

            // Clear current model state
            self.modelContainer = nil
        }

        // Reload the model to reset its internal conversation state
        do {
            try await self.ensureLoaded(modelId: currentModelId)
            // MLX conversation reset completed successfully
            NSLog("🔄 MLX conversation reset completed successfully")
        } catch {
            NSLog("❌ MLX conversation reset failed: \(error)")
        }
    }

    /// Clear model from memory
    func clearModel() async {
        modelContainer = nil
        currentModelId = nil
        // MLX model cleared
    }
}

/// Simplified MLX errors
enum SimplifiedMLXError: LocalizedError {
    case modelNotLoaded
    case generationFailed(String)
    case downloadCorrupted(String)
    case configurationMissing(String)
    case tokenizerCorrupted(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "MLX model not loaded"
        case .generationFailed(let message):
            return "MLX generation failed: \(message)"
        case .downloadCorrupted(let message):
            return "MLX model download corrupted: \(message)"
        case .configurationMissing(let message):
            return "MLX model configuration missing: \(message)"
        case .tokenizerCorrupted(let message):
            return "MLX model tokenizer corrupted: \(message)"
        }
    }
}
