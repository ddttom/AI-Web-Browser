import Combine
import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// MLX-based model service for efficient app distribution
/// Leverages MLX's built-in Hugging Face model downloading and caching
class MLXModelService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = MLXModelService()
    private static var isInitialized = false
    private static var isInitializationInProgress = false

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

    // MARK: - Properties

    private let fileManager = FileManager.default
    private var downloadTask: Task<Void, Error>?
    private var lastReadyCheck: Date?
    private let readyCheckThreshold: TimeInterval = 2.0
    private var initializationTask: Task<Void, Error>?
    private var readinessCompletionHandlers: [CheckedContinuation<Bool, Never>] = []
    private var initializationCompletionHandlers: [CheckedContinuation<Void, Never>] = []

    // MARK: - Initialization

    private init() {
        guard !MLXModelService.isInitialized else {
            NSLog("🛑 [SINGLETON] MLXModelService singleton already initialized - skipping duplicate init")
            AppLog.debug("🛑 [SINGLETON] MLXModelService singleton already initialized - preventing duplicate")
            return
        }
        MLXModelService.isInitialized = true
        
        AppLog.debug("🚀 [SINGLETON] MLXModelService initializing")
        AppLog.debug("🔍 [INIT STATE] Initial state: isModelReady=\(isModelReady), downloadState=\(downloadState)")

        Task { @MainActor in
            currentModel = MLXModelConfiguration.gemma3_2B_4bit
            AppLog.debug("🚀 [INIT] Default model set: gemma3_2B_4bit")
            AppLog.debug("🔍 [INIT STATE] After model set: isModelReady=\(isModelReady), downloadState=\(downloadState)")
        }

        Task {
            AppLog.debug("🔍 [INIT STATE] Starting smart initialization: isModelReady=\(isModelReady), downloadState=\(downloadState)")
            await performSmartStartupInitialization()
            AppLog.debug("🔍 [INIT STATE] Smart initialization complete: isModelReady=\(isModelReady), downloadState=\(downloadState)")
            AppLog.debug("🚀 [SINGLETON] MLXModelService ready")
        }
    }

    deinit {
        downloadTask?.cancel()
    }

    // MARK: - Public Interface

    /// Intelligent check: returns true if model is ready, false if download needed
    @MainActor
    func isAIReady() async -> Bool {
        let now = Date()
        if let lastCheck = lastReadyCheck, 
           now.timeIntervalSince(lastCheck) < readyCheckThreshold {
            return isModelReady && downloadState == .ready
        }
        
        lastReadyCheck = now
        return isModelReady && downloadState == .ready
    }
    
    /// Async method to wait for AI readiness without polling - much more efficient than isAIReady()
    @MainActor
    func waitForAIReadiness() async -> Bool {
        // If already ready, return immediately
        if isModelReady && downloadState == .ready {
            AppLog.debug("🚀 [ASYNC WAIT] AI already ready - returning immediately")
            return true
        }
        
        // If not ready, wait for completion
        return await withCheckedContinuation { continuation in
            AppLog.debug("🔄 [ASYNC WAIT] Waiting for AI initialization completion - no polling needed")
            readinessCompletionHandlers.append(continuation)
        }
    }
    
    /// Internal method to notify all waiting callers when AI becomes ready
    @MainActor
    private func notifyReadinessWaiters() {
        let isReady = isModelReady && downloadState == .ready
        AppLog.debug("📡 [ASYNC NOTIFY] Notifying \(readinessCompletionHandlers.count) waiters - AI ready: \(isReady)")
        
        for continuation in readinessCompletionHandlers {
            continuation.resume(returning: isReady)
        }
        readinessCompletionHandlers.removeAll()
    }
    
    /// Wait for initialization to complete asynchronously without polling
    private func waitForInitializationCompletion() async {
        if !Self.isInitializationInProgress {
            return  // Already completed
        }
        
        await withCheckedContinuation { continuation in
            AppLog.debug("🔄 [ASYNC WAIT] Waiting for initialization completion - no polling needed")
            initializationCompletionHandlers.append(continuation)
        }
    }
    
    /// Notify all waiters that initialization has completed
    @MainActor
    private func notifyInitializationCompletion() {
        AppLog.debug("📡 [ASYNC NOTIFY] Notifying \(initializationCompletionHandlers.count) initialization waiters")
        
        for continuation in initializationCompletionHandlers {
            continuation.resume(returning: ())
        }
        initializationCompletionHandlers.removeAll()
    }
    
    /// Load existing model files without checking for manual downloads
    private func loadExistingModel(model: MLXModelConfiguration) async {
        AppLog.debug("🚀 [SMART INIT] ✅ Complete model files detected - attempting to load existing model")
        
        do {
            // Try to load the existing model without triggering downloads
            downloadState = .validating
            downloadProgress = 0.5  // Start at 50% since files exist

            AppLog.debug("🚀 [SMART INIT] Loading model with Hugging Face repo format: \(model.huggingFaceRepo)")
            
            // Use the Hugging Face repository format for MLX loading
            try await SimplifiedMLXRunner.shared.ensureLoaded(modelId: model.huggingFaceRepo)

            AppLog.debug("🔍 [SMART INIT] Setting isModelReady = true")
            await MainActor.run {
                isModelReady = true
                downloadState = .ready
                downloadProgress = 1.0
            }
            AppLog.debug("🔍 [SMART INIT] Model state updated: isModelReady=\(isModelReady), downloadState=\(downloadState)")
            
            AppLog.essential("✅ AI model ready")
            await MainActor.run {
                notifyReadinessWaiters()
            }

            AppLog.debug("🚀 [SMART INIT] ✅ Successfully loaded existing model: \(model.name)")

        } catch {
            AppLog.debug("🚀 [SMART INIT] ❌ Failed to load existing model: \(error.localizedDescription)")
            AppLog.debug("🚀 [SMART INIT] Error suggests files exist but MLX validation failed")
            AppLog.debug("🚀 [SMART INIT] Will attempt fresh download to resolve validation issues")
            
            // Reset state for fresh download attempt
            await MainActor.run {
                downloadState = .notStarted
                downloadProgress = 0.0
            }
            
            // Fall through to standard initialization
            AppLog.debug("No existing model found - proceeding with standard initialization")
            await performIntelligentModelCheck()
        }
    }

    /// Get model configuration (replaces getModelPath for MLX compatibility)
    @MainActor
    func getModelConfiguration() async -> MLXModelConfiguration? {
        guard isModelReady else {
            return nil
        }
        return currentModel
    }

    /// Compatibility method for existing code (returns nil since MLX doesn't use file paths)
    func getModelPath() async -> URL? {
        // MLX models are managed internally and don't expose file paths
        // Return nil to indicate this service doesn't use file-based models
        return nil
    }

    /// Start AI initialization - downloads model if needed
    func initializeAI() async throws {
        // Quick early return if already fully initialized
        if isModelReady && downloadState == .ready && !Self.isInitializationInProgress {
            return
        }
        
        AppLog.debug("🔥 [INIT AI] initializeAI() called")
        AppLog.debug("🔍 [INIT AI] State check: isModelReady=\(isModelReady), downloadState=\(downloadState)")
        AppLog.debug("🔍 [INIT AI] Smart init in progress: \(Self.isInitializationInProgress)")

        // If already ready, no action needed - check internal state directly
        if isModelReady && downloadState == .ready {
            AppLog.debug("🔥 [INIT AI] MLX AI model already ready - no download needed")
            return
        } else {
            AppLog.debug("🔍 [INIT AI] Model not ready, proceeding with initialization checks...")
        }

        // If initialization is already in progress, wait for it to complete
        if Self.isInitializationInProgress {
            AppLog.debug("🛡️ [GUARD] initializeAI() blocked - smart initialization already in progress")
            AppLog.debug("🛡️ [GUARD] initializeAI() waiting for concurrent initialization to complete")

            // Wait for initialization to complete using async notification (no polling)
            await waitForInitializationCompletion()

            AppLog.debug("🔍 [GUARD] Smart init completed. Final state: isModelReady=\(isModelReady), downloadState=\(downloadState)")
            
            // Check again after waiting
            if await isAIReady() {
                AppLog.debug("🔥 [INIT AI] MLX AI model now ready after waiting for smart init")
                return
            } else {
                AppLog.debug("🔍 [GUARD] Model still not ready after smart init - may need actual download")
            }
        }

        // If currently downloading, just wait
        if downloadState == .downloading {
            AppLog.debug("🔥 [INIT AI] MLX AI model download in progress - waiting…")
            return
        }

        AppLog.debug(
            "🔥 [INIT AI] Redirecting to smart initialization instead of direct download...")

        // Use smart initialization instead of direct download
        await performSmartStartupInitialization()

        // Check if smart initialization succeeded
        if await isAIReady() {
            AppLog.debug("🔥 [INIT AI] ✅ Smart initialization succeeded")
            return
        }

        AppLog.debug(
            "🔥 [INIT AI] Smart initialization didn't complete - falling back to direct download")

        // Start download/loading process with enhanced error handling
        do {
            AppLog.debug("🔥 [INIT AI] Calling downloadModelIfNeeded() as fallback...")
            try await downloadModelIfNeeded()
        } catch {
            // Check if this is a recoverable tokenizer corruption error
            if error.localizedDescription.contains("tokenizer")
                || error.localizedDescription.contains("corrupted")
            {
                AppLog.debug(
                    "Detected tokenizer corruption during initialization, attempting recovery...")

                let modelConfig = await MainActor.run { currentModel }
                guard let model = modelConfig else {
                    throw MLXModelError.noModelConfiguration
                }

                // Perform aggressive cleanup and retry
                try await MLXCacheManager.shared.cleanupCorruptedCache(for: model.modelId)
                await SimplifiedMLXRunner.shared.clearModel()

                // Reset state and retry once
                await MainActor.run(resultType: Void.self) {
                    self.downloadState = .downloading
                    self.downloadProgress = 0.0
                }

                try await downloadModelIfNeeded()
                AppLog.debug("MLX model recovery during initialization successful")
            } else {
                // Re-throw non-recoverable errors
                throw error
            }
        }
    }

    /// Get download information for UI
    @MainActor
    func getDownloadInfo() async -> DownloadInfo {
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

    /// Smart startup initialization that respects manual downloads and existing models
    @MainActor
    private func performSmartStartupInitialization() async {
        guard !Self.isInitializationInProgress else {
            AppLog.debug("🛡️ [GUARD] Smart initialization already in progress - preventing concurrent execution")
            NSLog("🛡️ [GUARD] Smart initialization blocked - already running")
            return
        }
        
        Self.isInitializationInProgress = true
        AppLog.debug("🚀 [GUARD] Smart initialization guard acquired - proceeding with initialization")
        defer { 
            Self.isInitializationInProgress = false
            AppLog.debug("🔓 [GUARD] Smart initialization guard released")
            Task { @MainActor in
                self.notifyInitializationCompletion()
            }
        }
        
        AppLog.essential("🚀 AI model initialization started")
        AppLog.debug("🚀 [SMART INIT] === SMART STARTUP INITIALIZATION STARTED ===")

        guard let model = currentModel else {
            AppLog.error("🚀 [SMART INIT] ❌ No model configuration available")
            downloadState = .failed("No model configuration available")
            return
        }

        AppLog.debug("🚀 [SMART INIT] Model configuration loaded:")
        AppLog.debug("🚀 [SMART INIT]   Name: \(model.name)")
        AppLog.debug("🚀 [SMART INIT]   Model ID: \(model.modelId)")
        AppLog.debug("🚀 [SMART INIT]   HuggingFace Repo: \(model.huggingFaceRepo)")
        AppLog.debug("🚀 [SMART INIT]   Cache Directory Name: \(model.cacheDirectoryName)")
        AppLog.debug("🚀 [SMART INIT] Starting smart initialization for model: \(model.name)")
        downloadState = .checking

        // Step 1: FAST CHECK - Do model files already exist? (optimize for common case)
        AppLog.debug("🚀 [SMART INIT] Step 1: Quick model file existence check...")
        let hasCompleteFiles = await MLXCacheManager.shared.hasCompleteModelFiles(for: model)
        AppLog.debug("🚀 [SMART INIT] Quick check result: \(hasCompleteFiles)")

        if hasCompleteFiles {
            AppLog.essential("🚀 AI model found - loading existing files")
            AppLog.debug("🚀 [SMART INIT] ✅ Model files exist - skipping manual download check")
            // Skip manual download check since we have complete files
            await loadExistingModel(model: model)
            return
        }

        // Step 2: Files don't exist - check if manual download is currently active
        AppLog.debug("🚀 [SMART INIT] Step 2: Model files missing - checking for active manual downloads...")
        let isManualActive = await MLXCacheManager.shared.isManualDownloadActive()
        AppLog.debug("🚀 [SMART INIT] Manual download active: \(isManualActive)")

        if isManualActive {
            AppLog.debug("🚀 [SMART INIT] ⏳ Manual download detected - waiting for completion...")
            downloadState = .downloading
            downloadProgress = 0.0

            // Wait for manual download to complete
            await waitForManualDownloadCompletion(model: model)
            return
        } else {
            AppLog.debug("🚀 [SMART INIT] ✅ No manual download active - need to download model")
        }

        // Step 3: No existing model found, proceed with standard initialization

        // Step 3: No existing model found, proceed with standard initialization
        AppLog.debug("No existing model found - proceeding with standard initialization")
        await performIntelligentModelCheck()
    }

    /// Wait for manual download completion with monitoring
    @MainActor
    private func waitForManualDownloadCompletion(model: MLXModelConfiguration) async {
        let maxWaitTime: TimeInterval = 300  // 5 minutes maximum wait
        let checkInterval: TimeInterval = 5  // Check every 5 seconds
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < maxWaitTime {
            // Check if manual download is still active
            if !(await MLXCacheManager.shared.isManualDownloadActive()) {
                AppLog.debug("Manual download completed - checking for model files")

                // Give a moment for file system to settle
                try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds

                // Check if model files are now available using the proper model configuration
                if await MLXCacheManager.shared.hasCompleteModelFiles(for: model) {
                    AppLog.debug("Manual download successful - loading model")

                    do {
                        downloadState = .validating
                        downloadProgress = 0.8  // Start high since files exist

                        AppLog.debug("Loading manually downloaded model with Hugging Face repo format: \(model.huggingFaceRepo)")
                        try await SimplifiedMLXRunner.shared.ensureLoaded(modelId: model.huggingFaceRepo)

                        isModelReady = true
                        downloadState = .ready
                        downloadProgress = 1.0
                        
                        notifyReadinessWaiters()

                        AppLog.debug("Successfully loaded manually downloaded model: \(model.name)")
                        return

                    } catch {
                        AppLog.error(
                            "Failed to load manually downloaded model: \(error.localizedDescription)"
                        )
                        downloadState = .failed(
                            "Manual download completed but model loading failed: \(error.localizedDescription)"
                        )
                        return
                    }
                } else {
                    AppLog.debug(
                        "Manual download completed but model files not found - proceeding with automatic download"
                    )
                    await performIntelligentModelCheck()
                    return
                }
            }

            // Update progress to show we're waiting
            let elapsed = Date().timeIntervalSince(startTime)
            downloadProgress = min(0.9, elapsed / maxWaitTime)  // Progress up to 90% while waiting

            // Wait before next check
            try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
        }

        // Timeout reached
        AppLog.debug(
            "Timeout waiting for manual download - proceeding with automatic initialization")
        downloadState = .downloading
        downloadProgress = 0.0
        await performIntelligentModelCheck()
    }

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
            // First, check if model files already exist and are valid
            let isValid = await MLXCacheManager.shared.validateModelFiles(for: model.modelId)
            if isValid {
                AppLog.debug("Found valid cached model files for: \(model.name)")

                // Try to load the existing model
                downloadState = .validating
                downloadProgress = 0.5  // Start at 50% since files exist

                AppLog.debug("Loading cached model with Hugging Face repo format: \(model.huggingFaceRepo)")
                try await SimplifiedMLXRunner.shared.ensureLoaded(modelId: model.huggingFaceRepo)

                isModelReady = true
                downloadState = .ready
                downloadProgress = 1.0
                
                notifyReadinessWaiters()

                AppLog.debug("MLX model loaded from cache: \(model.name)")
                return
            }

            AppLog.debug("No valid cached model found, initiating download: \(model.name)")

            // No valid model found, need to download
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

            // Clean up any corrupted cache before attempting download
            do {
                try await MLXCacheManager.shared.cleanupCorruptedCache(for: model.modelId)
            } catch {
                AppLog.debug(
                    "Cache cleanup had issues but continuing: \(error.localizedDescription)")
                // Don't fail the download attempt just because cleanup had issues
            }

            try await SimplifiedMLXRunner.shared.ensureLoaded(modelId: model.modelId)

            progressTask.cancel()

            // Validate the downloaded model
            let downloadedIsValid = await MLXCacheManager.shared.validateModelFiles(
                for: model.modelId)
            if !downloadedIsValid {
                throw MLXModelError.validationFailed(
                    "Downloaded model files are incomplete or corrupted")
            }

            // If we got here, the model is ready
            isModelReady = true
            downloadState = .ready
            downloadProgress = 1.0
            
            notifyReadinessWaiters()

            AppLog.debug("MLX model downloaded and validated: \(model.name)")

        } catch {
            AppLog.error("MLX model check failed: \(error.localizedDescription)")

            // Check if this is a tokenizer corruption error that we can recover from
            if error.localizedDescription.contains("tokenizer")
                || error.localizedDescription.contains("corrupted")
            {
                AppLog.debug("Detected tokenizer corruption, attempting automatic recovery...")

                // Perform aggressive cleanup
                do {
                    try await MLXCacheManager.shared.cleanupCorruptedCache(for: model.modelId)
                    AppLog.debug("Cache cleanup completed, attempting retry...")

                    // Clear the MLX runner's model state
                    await SimplifiedMLXRunner.shared.clearModel()

                    // Retry the download once more
                    downloadState = .downloading
                    downloadProgress = 0.0

                    try await SimplifiedMLXRunner.shared.ensureLoaded(modelId: model.modelId)

                    // Validate the retry attempt
                    let retryIsValid = await MLXCacheManager.shared.validateModelFiles(
                        for: model.modelId)
                    if retryIsValid {
                        isModelReady = true
                        downloadState = .ready
                        downloadProgress = 1.0
                        
                        notifyReadinessWaiters()
                        
                        AppLog.debug("MLX model recovery successful: \(model.name)")
                        return
                    } else {
                        throw MLXModelError.validationFailed(
                            "Model recovery failed - files still corrupted after cleanup")
                    }

                } catch {
                    AppLog.error("MLX model recovery failed: \(error.localizedDescription)")
                    downloadState = .failed(
                        "Automatic recovery failed: \(error.localizedDescription). Please try manual cache cleanup in Settings."
                    )
                    isModelReady = false
                    downloadProgress = 0.0
                }
            } else {
                // Non-recoverable error
                downloadState = .failed(error.localizedDescription)
                isModelReady = false
                downloadProgress = 0.0

                // Still try to clean up any corrupted files
                do {
                    try await MLXCacheManager.shared.cleanupCorruptedCache(for: model.modelId)
                } catch {
                    AppLog.error(
                        "Failed to cleanup after model check failure: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    @MainActor
    private func downloadModelIfNeeded() async throws {
        AppLog.debug("📥 [DOWNLOAD] === downloadModelIfNeeded() STARTED ===")

        guard let model = currentModel else {
            AppLog.debug("📥 [DOWNLOAD] ❌ No model configuration available")
            throw MLXModelError.noModelConfiguration
        }

        AppLog.debug("📥 [DOWNLOAD] Model configuration:")
        AppLog.debug("📥 [DOWNLOAD]   Name: \(model.name)")
        AppLog.debug("📥 [DOWNLOAD]   Model ID: \(model.modelId)")
        AppLog.debug("📥 [DOWNLOAD]   HuggingFace Repo: \(model.huggingFaceRepo)")
        AppLog.debug("📥 [DOWNLOAD]   Cache Directory Name: \(model.cacheDirectoryName)")

        downloadState = .downloading
        downloadProgress = 0.0

        AppLog.debug("📥 [DOWNLOAD] Download state set to downloading, progress reset to 0.0")

        if AppLog.isVerboseEnabled {
            AppLog.debug(
                "Starting MLX model download: \(model.name) (~\(String(format: "%.1f", model.estimatedSizeGB)) GB)"
            )
        }
        if AppLog.isVerboseEnabled {
            AppLog.debug("One-time download; future launches will be instant")
        }

        // Enhanced download with retry logic and cache cleanup
        let maxRetries = 3
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                AppLog.debug("📥 [DOWNLOAD] === ATTEMPT \(attempt) of \(maxRetries) ===")
                AppLog.debug("📥 [DOWNLOAD] Model: \(model.name)")
                AppLog.debug("📥 [DOWNLOAD] Model ID: \(model.modelId)")
                AppLog.debug("📥 [DOWNLOAD] HuggingFace Repo: \(model.huggingFaceRepo)")

                // CRITICAL: Check if files already exist before attempting download
                AppLog.debug("📥 [DOWNLOAD] Step 1: Checking for existing files before download...")
                let existingFiles = await MLXCacheManager.shared.hasCompleteModelFiles(for: model)
                AppLog.debug("📥 [DOWNLOAD] Existing files check result: \(existingFiles)")

                if existingFiles {
                    AppLog.debug("📥 [DOWNLOAD] ✅ FILES ALREADY EXIST - Should not be downloading!")
                    AppLog.debug("📥 [DOWNLOAD] Attempting to load existing files instead...")

                    // Try to load existing files using proper Hugging Face format
                    AppLog.debug("📥 [DOWNLOAD] Loading existing model with Hugging Face repo format: \(model.huggingFaceRepo)")
                    try await SimplifiedMLXRunner.shared.ensureLoaded(modelId: model.huggingFaceRepo)

                    // If successful, mark as ready
                    isModelReady = true
                    downloadState = .ready
                    downloadProgress = 1.0
                    
                    notifyReadinessWaiters()
                    
                    AppLog.debug("📥 [DOWNLOAD] ✅ Successfully loaded existing model files")
                    return
                }

                // Clean up any corrupted cache before attempting download
                AppLog.debug("📥 [DOWNLOAD] Step 2: Cleaning corrupted cache...")
                do {
                    try await MLXCacheManager.shared.cleanupCorruptedCache(for: model.modelId)
                    AppLog.debug("📥 [DOWNLOAD] Cache cleanup completed successfully")
                } catch {
                    AppLog.debug(
                        "📥 [DOWNLOAD] Cache cleanup had issues but continuing: \(error.localizedDescription)"
                    )
                    // Don't fail the download attempt just because cleanup had issues
                }

                // Attempt download with enhanced error handling
                AppLog.debug("📥 [DOWNLOAD] Step 3: Attempting download with validation...")
                try await performDownloadWithValidation(model: model)

                // If we get here, download was successful
                isModelReady = true
                downloadState = .ready
                downloadProgress = 1.0
                notifyReadinessWaiters()

                AppLog.debug("MLX AI model download completed successfully on attempt \(attempt)")
                return

            } catch {
                lastError = error
                AppLog.error(
                    "📥 [DOWNLOAD] ❌ Download attempt \(attempt) failed: \(error.localizedDescription)"
                )

                // Enhanced error categorization
                let errorDescription = error.localizedDescription.lowercased()
                if errorDescription.contains("file") && errorDescription.contains("not found") {
                    AppLog.error("📥 [DOWNLOAD] 🔍 ERROR CATEGORY: File Not Found")
                    AppLog.error("📥 [DOWNLOAD] Expected model path: \(model.huggingFaceRepo)")
                    AppLog.error("📥 [DOWNLOAD] Cache directory: \(model.cacheDirectoryName)")

                    // Check what files actually exist
                    let homeDir = FileManager.default.homeDirectoryForCurrentUser
                    let expectedPath = homeDir.appendingPathComponent(
                        ".cache/huggingface/hub/\(model.cacheDirectoryName)/snapshots/main")
                    AppLog.error("📥 [DOWNLOAD] Expected file location: \(expectedPath.path)")
                    AppLog.error(
                        "📥 [DOWNLOAD] Directory exists: \(FileManager.default.fileExists(atPath: expectedPath.path))"
                    )

                } else if errorDescription.contains("corrupt")
                    || errorDescription.contains("incomplete")
                {
                    AppLog.error("📥 [DOWNLOAD] 🔍 ERROR CATEGORY: File Corruption/Incomplete")
                    AppLog.error("📥 [DOWNLOAD] This suggests files exist but are invalid")

                    // Perform detailed file integrity check
                    let hasFiles = await MLXCacheManager.shared.hasCompleteModelFiles(for: model)
                    AppLog.error("📥 [DOWNLOAD] hasCompleteModelFiles result: \(hasFiles)")

                } else {
                    AppLog.error("📥 [DOWNLOAD] 🔍 ERROR CATEGORY: Other/Unknown")
                    AppLog.error("📥 [DOWNLOAD] Full error: \(error)")
                }

                // Cancel any ongoing progress monitoring
                downloadTask?.cancel()
                downloadTask = nil

                // Clean up failed download artifacts
                do {
                    try await MLXCacheManager.shared.cleanupCorruptedCache(for: model.modelId)
                } catch {
                    AppLog.error(
                        "Failed to cleanup after download failure: \(error.localizedDescription)")
                }

                if attempt < maxRetries {
                    // Exponential backoff: 2^attempt seconds
                    let delay = pow(2.0, Double(attempt))
                    AppLog.debug("Retrying download in \(delay) seconds...")

                    downloadState = .downloading
                    downloadProgress = 0.0

                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    // Final failure
                    downloadState = .failed(
                        "Failed after \(maxRetries) attempts: \(error.localizedDescription)")
                    isModelReady = false
                    downloadProgress = 0.0
                }
            }
        }

        // If we get here, all retries failed
        let finalError = MLXModelError.downloadFailed(
            "Download failed after \(maxRetries) attempts. Last error: \(lastError?.localizedDescription ?? "Unknown error")"
        )
        AppLog.error("MLX AI model download failed permanently: \(finalError.localizedDescription)")
        throw finalError
    }

    /// Perform download with validation and progress monitoring
    @MainActor
    private func performDownloadWithValidation(model: MLXModelConfiguration) async throws {
        // Validate cache state before download
        let cacheStatus = await MLXCacheManager.shared.getCacheStatus()
        AppLog.debug(
            "Cache status before download: \(cacheStatus.formattedSize), \(cacheStatus.modelCount) models"
        )

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
        AppLog.debug("📥 [DOWNLOAD VALIDATION] Loading model with Hugging Face repo format: \(model.huggingFaceRepo)")
        try await SimplifiedMLXRunner.shared.ensureLoaded(modelId: model.huggingFaceRepo)

        // Cancel the progress monitoring
        downloadTask?.cancel()
        downloadTask = nil

        // Validate the downloaded model
        let isValid = await MLXCacheManager.shared.validateModelFiles(for: model.modelId)
        if !isValid {
            throw MLXModelError.validationFailed(
                "Downloaded model files are incomplete or corrupted")
        }

        AppLog.debug("Model download and validation completed successfully")
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
    case manualDownloadConflict(String)

    var errorDescription: String? {
        switch self {
        case .noModelConfiguration:
            return "No model configuration available"
        case .downloadFailed(let message):
            return "MLX model download failed: \(message)"
        case .validationFailed(let message):
            return "MLX model validation failed: \(message)"
        case .manualDownloadConflict(let message):
            return "Manual download coordination issue: \(message)"
        }
    }
}
