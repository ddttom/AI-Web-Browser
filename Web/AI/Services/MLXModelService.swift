import Combine
import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// MLX-based model service for efficient app distribution
/// Leverages MLX's built-in Hugging Face model downloading and caching
class MLXModelService: ObservableObject {

    // MARK: - Published Properties

    @Published var isModelReady: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadState: DownloadState = .notStarted
    @Published var currentModel: MLXModelConfiguration?

    // MARK: - Types

    enum DownloadState: Equatable {
        case notStarted  // No model detected, download needed
        case checking  // Checking for existing model
        case downloading  // Currently downloading
        case validating  // Validating downloaded model
        case ready  // Model available and ready
        case failed(String)  // Download or validation failed

        static func == (lhs: DownloadState, rhs: DownloadState) -> Bool {
            switch (lhs, rhs) {
            case (.notStarted, .notStarted),
                (.checking, .checking),
                (.downloading, .downloading),
                (.validating, .validating),
                (.ready, .ready):
                return true
            case (.failed(let lhsMsg), .failed(let rhsMsg)):
                return lhsMsg == rhsMsg
            default:
                return false
            }
        }
    }

    struct MLXModelConfiguration {
        let name: String
        let modelId: String
        let estimatedSizeGB: Double
        let modelKey: String

        // Llama 3.2 1B 4-bit configuration (MLX optimized)
        static let llama3_2_1B_4bit = MLXModelConfiguration(
            name: "Llama 3.2 1B 4-bit (MLX)",
            modelId: "llama3_2_1B_4bit",
            estimatedSizeGB: 0.8,  // 1B model is smaller
            modelKey: "llama3_2_1B_4bit"
        )

        // Llama 3.2 3B 4-bit configuration (larger option)
        static let llama3_2_3B_4bit = MLXModelConfiguration(
            name: "Llama 3.2 3B 4-bit (MLX)",
            modelId: "llama3_2_3B_4bit",
            estimatedSizeGB: 1.9,
            modelKey: "llama3_2_3B_4bit"
        )

        // Gemma 2 2B 4-bit configuration (high quality, compact)
        static let gemma3_2B_4bit = MLXModelConfiguration(
            name: "Gemma 2 2B 4-bit (MLX)",
            modelId: "gemma3_2B_4bit",
            estimatedSizeGB: 1.4,
            modelKey: "gemma3_2B_4bit"
        )

        // Gemma 2 9B 4-bit configuration (highest quality)
        static let gemma3_9B_4bit = MLXModelConfiguration(
            name: "Gemma 2 9B 4-bit (MLX)",
            modelId: "gemma3_9B_4bit",
            estimatedSizeGB: 5.2,
            modelKey: "gemma3_9B_4bit"
        )
    }

    // MARK: - Properties

    private let fileManager = FileManager.default
    private var downloadTask: Task<Void, Error>?

    // MARK: - Initialization

    init() {
        // Set default model configuration
        Task { @MainActor in
            currentModel = MLXModelConfiguration.gemma3_2B_4bit
        }

        // Immediately check for existing model on initialization
        Task {
            await performIntelligentModelCheck()
        }

        AppLog.debug("MLXModelService init - checking for existing MLX AI model…")
    }

    deinit {
        downloadTask?.cancel()
    }

    // MARK: - Public Interface

    /// Intelligent check: returns true if model is ready, false if download needed
    func isAIReady() async -> Bool {
        return await MainActor.run { isModelReady && downloadState == .ready }
    }

    /// Get model configuration (replaces getModelPath for MLX compatibility)
    func getModelConfiguration() async -> MLXModelConfiguration? {
        return await MainActor.run {
            guard isModelReady else {
                return nil
            }
            return currentModel
        }
    }

    /// Compatibility method for existing code (returns nil since MLX doesn't use file paths)
    func getModelPath() async -> URL? {
        // MLX models are managed internally and don't expose file paths
        // Return nil to indicate this service doesn't use file-based models
        return nil
    }

    /// Start AI initialization - downloads model if needed
    func initializeAI() async throws {
        // If already ready, no action needed
        if await isAIReady() {
            AppLog.debug("MLX AI model already ready - no download needed")
            return
        }

        // If currently downloading, just wait
        if downloadState == .downloading {
            if AppLog.isVerboseEnabled {
                AppLog.debug("MLX AI model download in progress - waiting…")
            }
            return
        }

        // Start download/loading process
        try await downloadModelIfNeeded()
    }

    /// Get download information for UI
    func getDownloadInfo() async -> DownloadInfo {
        return await MainActor.run {
            guard let model = currentModel else {
                return DownloadInfo(
                    modelName: "Unknown Model",
                    sizeGB: 0.0,
                    isDownloadNeeded: true
                )
            }

            return DownloadInfo(
                modelName: model.name,
                sizeGB: model.estimatedSizeGB,
                isDownloadNeeded: !isModelReady || downloadState != .ready
            )
        }
    }

    /// Cancel ongoing download
    @MainActor
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil

        downloadState = .notStarted
        downloadProgress = 0.0

        NSLog("❌ MLX AI model download cancelled by user")
    }

    /// Switch to a different model configuration
    @MainActor
    func switchToModel(_ configuration: MLXModelConfiguration) async {
        guard configuration.modelId != currentModel?.modelId else {
            NSLog("ℹ️ Already using model: \(configuration.name)")
            return
        }

        NSLog("🔄 Switching to model: \(configuration.name)")

        // Clear current model state
        isModelReady = false
        downloadState = .notStarted
        downloadProgress = 0.0
        currentModel = configuration

        // Clear the MLX runner's model to force reload
        await SimplifiedMLXRunner.shared.clearModel()

        // Check if new model is available
        await performIntelligentModelCheck()
    }

    // MARK: - Private Methods

    /// Intelligent model detection and validation
    @MainActor
    private func performIntelligentModelCheck() async {
        downloadState = .checking

        guard let model = currentModel else {
            downloadState = .failed("No model configuration available")
            return
        }

        if AppLog.isVerboseEnabled {
            AppLog.debug("Checking MLX model availability: \(model.name)")
        }

        do {
            // Try to ensure the model is loaded - this will trigger MLX to download if needed
            downloadState = .downloading
            downloadProgress = 0.0

            // Monitor progress during loading
            let progressTask = Task {
                while !Task.isCancelled {
                    let progress = SimplifiedMLXRunner.shared.loadProgress
                    await MainActor.run {
                        self.downloadProgress = Double(progress)
                    }

                    if progress >= 1.0 {
                        break
                    }

                    try await Task.sleep(nanoseconds: 100_000_000)  // Check every 0.1 seconds
                }
            }

            try await SimplifiedMLXRunner.shared.ensureLoaded(modelId: model.modelId)

            progressTask.cancel()

            // If we got here, the model is ready
            isModelReady = true
            downloadState = .ready
            downloadProgress = 1.0

            AppLog.debug("MLX model validated and ready: \(model.name)")

        } catch {
            downloadState = .failed(error.localizedDescription)
            isModelReady = false
            downloadProgress = 0.0

            AppLog.error("MLX model check failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func downloadModelIfNeeded() async throws {
        guard let model = currentModel else {
            throw MLXModelError.noModelConfiguration
        }

        downloadState = .downloading
        downloadProgress = 0.0

        if AppLog.isVerboseEnabled {
            AppLog.debug(
                "Starting MLX model download: \(model.name) (~\(String(format: "%.1f", model.estimatedSizeGB)) GB)"
            )
        }
        if AppLog.isVerboseEnabled {
            AppLog.debug("One-time download; future launches will be instant")
        }

        do {
            // Connect to SimplifiedMLXRunner progress updates
            downloadTask = Task {
                // Monitor SimplifiedMLXRunner's loadProgress
                while !Task.isCancelled {
                    let progress = SimplifiedMLXRunner.shared.loadProgress
                    await MainActor.run {
                        self.downloadProgress = Double(progress)
                    }

                    // Check if loading is complete
                    if progress >= 1.0 {
                        break
                    }

                    try await Task.sleep(nanoseconds: 100_000_000)  // Check every 0.1 seconds
                }
            }

            // Start the actual model loading - this will update loadProgress automatically
            try await SimplifiedMLXRunner.shared.ensureLoaded(modelId: model.modelId)

            // Cancel the progress monitoring
            downloadTask?.cancel()
            downloadTask = nil

            isModelReady = true
            downloadState = .ready
            downloadProgress = 1.0

            AppLog.debug("MLX AI model download completed successfully; AI ready")

        } catch {
            downloadTask?.cancel()
            downloadTask = nil

            downloadState = .failed(error.localizedDescription)
            isModelReady = false
            downloadProgress = 0.0

            AppLog.error("MLX AI model download failed: \(error.localizedDescription)")
            throw error
        }
    }
}

// MARK: - Supporting Types

struct DownloadInfo {
    let modelName: String
    let sizeGB: Double
    let isDownloadNeeded: Bool

    var formattedSize: String {
        return String(format: "%.1f GB", sizeGB)
    }

    var statusMessage: String {
        if isDownloadNeeded {
            return "AI model download required (\(formattedSize))"
        } else {
            return "AI model ready"
        }
    }
}

enum MLXModelError: LocalizedError {
    case noModelConfiguration
    case downloadFailed(String)
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noModelConfiguration:
            return "No model configuration available"
        case .downloadFailed(let message):
            return "MLX model download failed: \(message)"
        case .validationFailed(let message):
            return "MLX model validation failed: \(message)"
        }
    }
}
