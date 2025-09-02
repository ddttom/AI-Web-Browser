import Foundation

/// Utility class for managing MLX model cache, handling cleanup of corrupted downloads
/// and validation of model files to prevent the tokenizer.json incomplete file errors
class MLXCacheManager {
    static let shared = MLXCacheManager()

    private let fileManager = FileManager.default

    private init() {}

    // MARK: - Cache Directories

    private var _cachedDirectories: [URL]?
    private var lastDirectoryCheck: Date?
    private let directoryCheckThreshold: TimeInterval = 30.0
    
    /// Get all potential cache directories where MLX models might be stored
    private var cacheDirectories: [URL] {
        let now = Date()
        
        if let cached = _cachedDirectories,
           let lastCheck = lastDirectoryCheck,
           now.timeIntervalSince(lastCheck) < directoryCheckThreshold {
            return cached
        }
        
        var directories: [URL] = []

        let homeDir = fileManager.homeDirectoryForCurrentUser
        let hfCacheDir = homeDir.appendingPathComponent(".cache/huggingface/hub")
        directories.append(hfCacheDir)

        if let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let mlxCacheDir = cacheDir.appendingPathComponent("MLXCache")
            directories.append(mlxCacheDir)
        }

        if let systemCacheDir = fileManager.urls(for: .cachesDirectory, in: .systemDomainMask).first {
            let sysCacheDir = systemCacheDir.appendingPathComponent("MLXCache")
            directories.append(sysCacheDir)
        }

        let existingDirs = directories.filter { fileManager.fileExists(atPath: $0.path) }
        
        _cachedDirectories = existingDirs
        lastDirectoryCheck = now
        
        if AppLog.isVerboseEnabled {
            AppLog.debug("🔍 [CACHE DIRS] Found \(existingDirs.count) cache directories")
        }

        return existingDirs
    }

    // MARK: - Public Interface

    private var lastManualCheck: Date?
    private var cachedManualCheckResult: Bool = false
    private let manualCheckThreshold: TimeInterval = 2.0
    
    /// Check if a manual download process is currently active
    func isManualDownloadActive() async -> Bool {
        let now = Date()
        if let lastCheck = lastManualCheck,
           now.timeIntervalSince(lastCheck) < manualCheckThreshold {
            return cachedManualCheckResult
        }
        
        if AppLog.isVerboseEnabled {
            AppLog.debug("🚀 [SMART INIT] Checking for manual download activity...")
        }
        
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let lockFile = homeDir.appendingPathComponent(
            ".cache/huggingface/hub/models--mlx-community--gemma-2-2b-it-4bit/.manual_download_lock"
        )

        if fileManager.fileExists(atPath: lockFile.path) {
            if AppLog.isVerboseEnabled {
                AppLog.debug("🚀 [SMART INIT] ✅ Manual download lock file detected")
            }
            cachedManualCheckResult = true
            lastManualCheck = now
            return true
        }

        do {
            let task = Process()
            task.launchPath = "/usr/bin/pgrep"
            task.arguments = ["-f", "manual_model_download"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            
            try task.run()
            task.waitUntilExit()
            
            let isActive = task.terminationStatus == 0
            cachedManualCheckResult = isActive
            lastManualCheck = now
            
            if AppLog.isVerboseEnabled {
                AppLog.debug("🚀 [SMART INIT] Manual download active: \(isActive)")
            }
            
            return isActive
            
        } catch {
            cachedManualCheckResult = false
            lastManualCheck = now
            return false
        }
    }

    /// Check if model files exist and are complete (without validation overhead) - New method with model configuration
    func hasCompleteModelFiles(for modelConfig: MLXModelConfiguration) async -> Bool {
        AppLog.debug(
            "🔍 [CACHE DEBUG] Checking for complete model files for ID: \(modelConfig.modelId)")
        // Updated required files list to match manual download script
        let requiredFiles = [
            "config.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "special_tokens_map.json",
            "model.safetensors",
        ]

        AppLog.debug("🔍 [CACHE DEBUG] Searching in \(cacheDirectories.count) cache directories")
        for (index, cacheDir) in cacheDirectories.enumerated() {
            AppLog.debug("🔍 [CACHE DEBUG] Checking cache directory \(index + 1): \(cacheDir.path)")

            if let modelDir = await findModelDirectory(in: cacheDir, for: modelConfig) {
                AppLog.debug("🔍 [CACHE DEBUG] Found model directory: \(modelDir.path)")
                // Quick file existence check without full validation
                var allFilesPresent = true
                AppLog.debug("🔍 [CACHE DEBUG] Checking required files: \(requiredFiles)")

                for fileName in requiredFiles {
                    let filePath = modelDir.appendingPathComponent(fileName)
                    AppLog.debug("🔍 [CACHE DEBUG] Checking file: \(filePath.path)")

                    if !fileManager.fileExists(atPath: filePath.path) {
                        AppLog.debug("🔍 [CACHE DEBUG] ❌ Missing file: \(fileName)")
                        allFilesPresent = false
                        break
                    }

                    // Quick size check - files should not be empty
                    do {
                        let attributes = try fileManager.attributesOfItem(atPath: filePath.path)
                        let fileSize = attributes[.size] as? Int64 ?? 0
                        AppLog.debug(
                            "🔍 [CACHE DEBUG] ✅ Found file: \(fileName) (\(fileSize) bytes)")

                        if fileSize < 10 {  // Files should be larger than 10 bytes
                            AppLog.debug(
                                "🔍 [CACHE DEBUG] ❌ File too small: \(fileName) (\(fileSize) bytes)")
                            allFilesPresent = false
                            break
                        }
                    } catch {
                        AppLog.debug(
                            "🔍 [CACHE DEBUG] ❌ Error checking file: \(fileName) - \(error.localizedDescription)"
                        )
                        allFilesPresent = false
                        break
                    }
                }

                if allFilesPresent {
                    AppLog.debug(
                        "🔍 [CACHE DEBUG] ✅ All required files found for: \(modelConfig.modelId)")
                    return true
                } else {
                    AppLog.debug("🔍 [CACHE DEBUG] ❌ Some files missing for: \(modelConfig.modelId)")
                }
            }
        }

        return false
    }

    /// Legacy method for backward compatibility
    func hasCompleteModelFiles(for modelId: String) async -> Bool {
        AppLog.debug("🔍 [LEGACY CHECK] Called with legacy modelId: \(modelId)")

        let legacyConfig = MLXModelConfiguration(
            name: "Legacy Model",
            modelId: modelId,
            huggingFaceRepo: modelId,
            cacheDirectoryName: getCacheDirNameFromModelId(modelId),
            estimatedSizeGB: 1.0,
            modelKey: modelId
        )

        AppLog.debug("🔍 [LEGACY CHECK] Created legacy config:")
        AppLog.debug("🔍 [LEGACY CHECK]   Cache dir name: \(legacyConfig.cacheDirectoryName)")
        AppLog.debug("🔍 [LEGACY CHECK]   HF repo: \(legacyConfig.huggingFaceRepo)")

        let result = await hasCompleteModelFiles(for: legacyConfig)
        AppLog.debug("🔍 [LEGACY CHECK] Legacy check result: \(result)")

        return result
    }

    /// Validate that manually downloaded files are accessible to the app
    func validateManualDownloadAccessibility(for modelConfig: MLXModelConfiguration) async -> Bool {
        AppLog.debug("🔍 [MANUAL VALIDATE] === Validating manual download accessibility ===")
        AppLog.debug("🔍 [MANUAL VALIDATE] Model: \(modelConfig.modelId)")

        // Check the exact path where manual downloads are stored
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let manualDownloadPath =
            homeDir
            .appendingPathComponent(".cache/huggingface/hub")
            .appendingPathComponent(modelConfig.cacheDirectoryName)
            .appendingPathComponent("snapshots/main")

        AppLog.debug(
            "🔍 [MANUAL VALIDATE] Expected manual download path: \(manualDownloadPath.path)")
        AppLog.debug(
            "🔍 [MANUAL VALIDATE] Directory exists: \(fileManager.fileExists(atPath: manualDownloadPath.path))"
        )

        guard fileManager.fileExists(atPath: manualDownloadPath.path) else {
            AppLog.debug("🔍 [MANUAL VALIDATE] ❌ Manual download directory not found")
            return false
        }

        // Check all required files
        let requiredFiles = [
            "config.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "special_tokens_map.json",
            "model.safetensors",
        ]

        AppLog.debug("🔍 [MANUAL VALIDATE] Checking \(requiredFiles.count) required files...")

        for fileName in requiredFiles {
            let filePath = manualDownloadPath.appendingPathComponent(fileName)
            AppLog.debug("🔍 [MANUAL VALIDATE] Checking: \(filePath.path)")

            guard fileManager.fileExists(atPath: filePath.path) else {
                AppLog.debug("🔍 [MANUAL VALIDATE] ❌ Missing file: \(fileName)")
                return false
            }

            // Check file size and readability
            do {
                let attributes = try fileManager.attributesOfItem(atPath: filePath.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                let isReadable = fileManager.isReadableFile(atPath: filePath.path)

                AppLog.debug(
                    "🔍 [MANUAL VALIDATE] ✅ \(fileName): \(fileSize) bytes, readable: \(isReadable)")

                if fileSize < 10 {
                    AppLog.debug("🔍 [MANUAL VALIDATE] ❌ File too small: \(fileName)")
                    return false
                }

                if !isReadable {
                    AppLog.debug("🔍 [MANUAL VALIDATE] ❌ File not readable: \(fileName)")
                    return false
                }

            } catch {
                AppLog.debug(
                    "🔍 [MANUAL VALIDATE] ❌ Error checking \(fileName): \(error.localizedDescription)"
                )
                return false
            }
        }

        AppLog.debug("🔍 [MANUAL VALIDATE] ✅ All manual download files validated successfully")
        return true
    }

    /// Clean up corrupted cache files for a specific model
    func cleanupCorruptedCache(for modelId: String) async throws {
        AppLog.debug("Starting cache cleanup for model: \(modelId)")

        var cleanupErrors: [String] = []

        for cacheDir in cacheDirectories {
            do {
                try await cleanupIncompleteFiles(in: cacheDir, for: modelId)
            } catch {
                let errorMsg = "Failed to cleanup \(cacheDir.path): \(error.localizedDescription)"
                AppLog.debug(errorMsg)
                cleanupErrors.append(errorMsg)
                // Continue with other directories instead of failing completely
            }
        }

        // Also perform aggressive cleanup of tokenizer files specifically
        do {
            try await cleanupTokenizerFiles(for: modelId)
        } catch {
            let errorMsg = "Failed to cleanup tokenizer files: \(error.localizedDescription)"
            AppLog.debug(errorMsg)
            cleanupErrors.append(errorMsg)
        }

        if cleanupErrors.isEmpty {
            AppLog.debug("Cache cleanup completed successfully for model: \(modelId)")
        } else {
            AppLog.debug("Cache cleanup completed with some errors for model: \(modelId)")
            // Don't throw error - partial cleanup is better than no cleanup
        }
    }

    /// Aggressively clean up tokenizer-related files that might be corrupted
    private func cleanupTokenizerFiles(for modelId: String) async throws {
        AppLog.debug("Performing aggressive tokenizer cleanup for model: \(modelId)")

        for cacheDir in cacheDirectories {
            guard fileManager.fileExists(atPath: cacheDir.path) else { continue }

            // Find model directories
            if let modelDir = await findModelDirectory(in: cacheDir, for: modelId) {
                let tokenizerFiles = [
                    "tokenizer.json",
                    "tokenizer_config.json",
                    "special_tokens_map.json",
                    "vocab.json",
                ]

                for fileName in tokenizerFiles {
                    let filePath = modelDir.appendingPathComponent(fileName)
                    if fileManager.fileExists(atPath: filePath.path) {
                        do {
                            // Check if file is corrupted or incomplete
                            if await isFileIncompleteOrCorrupted(filePath) {
                                try fileManager.removeItem(at: filePath)
                                AppLog.debug("Removed corrupted tokenizer file: \(fileName)")
                            }
                        } catch {
                            AppLog.debug(
                                "Failed to remove tokenizer file \(fileName): \(error.localizedDescription)"
                            )
                        }
                    }
                }

                // Also remove any .incomplete files in the model directory
                do {
                    let contents = try fileManager.contentsOfDirectory(
                        at: modelDir,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    )

                    for item in contents {
                        if item.lastPathComponent.contains(".incomplete") {
                            try fileManager.removeItem(at: item)
                            AppLog.debug("Removed incomplete file: \(item.lastPathComponent)")
                        }
                    }
                } catch {
                    AppLog.debug(
                        "Error cleaning incomplete files in model directory: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    /// Validate that all required model files exist and are complete
    func validateModelFiles(for modelId: String) async -> Bool {
        // Updated to match manual download script requirements - all files are required
        let requiredFiles = [
            "config.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "special_tokens_map.json",
            "model.safetensors",
        ]

        for cacheDir in cacheDirectories {
            if let modelDir = await findModelDirectory(in: cacheDir, for: modelId) {
                // Check required files
                for fileName in requiredFiles {
                    let filePath = modelDir.appendingPathComponent(fileName)
                    if !fileManager.fileExists(atPath: filePath.path) {
                        AppLog.debug("Missing required file: \(fileName) in \(modelDir.path)")
                        return false
                    }

                    // Check file is not empty and not incomplete
                    if await isFileIncompleteOrCorrupted(filePath) {
                        AppLog.debug("Corrupted file detected: \(fileName)")
                        return false
                    }
                }

                // All files are now required - no optional files to check separately

                AppLog.debug("Model validation passed for: \(modelId)")
                return true
            }
        }

        AppLog.debug("No valid model directory found for: \(modelId)")
        return false
    }

    /// Get cache status information for debugging
    func getCacheStatus() async -> CacheStatus {
        var totalSize: Int64 = 0
        var modelCount = 0
        var corruptedFiles: [String] = []

        for cacheDir in cacheDirectories {
            let (size, models, corrupted) = await analyzeCacheDirectory(cacheDir)
            totalSize += size
            modelCount += models
            corruptedFiles.append(contentsOf: corrupted)
        }

        return CacheStatus(
            totalSizeBytes: totalSize,
            modelCount: modelCount,
            corruptedFiles: corruptedFiles,
            cacheDirectories: cacheDirectories.map { $0.path }
        )
    }

    /// Perform comprehensive cache cleanup
    func performFullCacheCleanup() async throws {
        AppLog.debug("Starting full cache cleanup")

        for cacheDir in cacheDirectories {
            try await cleanupAllIncompleteFiles(in: cacheDir)
        }

        AppLog.debug("Full cache cleanup completed")
    }

    // MARK: - Private Methods

    /// Clean up incomplete files in a specific directory for a model
    private func cleanupIncompleteFiles(in directory: URL, for modelId: String) async throws {
        guard fileManager.fileExists(atPath: directory.path) else {
            AppLog.debug("Cache directory does not exist: \(directory.path)")
            return
        }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )

            for item in contents {
                let fileName = item.lastPathComponent

                // Remove incomplete files
                if fileName.contains(".incomplete") {
                    try fileManager.removeItem(at: item)
                    AppLog.debug("Removed incomplete file: \(fileName)")
                    continue
                }

                // Remove corrupted model directories
                if fileName.contains(modelId) || fileName.contains("models--") {
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory)
                        && isDirectory.boolValue
                    {
                        if await isModelDirectoryCorrupted(item) {
                            do {
                                try fileManager.removeItem(at: item)
                                AppLog.debug("Removed corrupted model directory: \(fileName)")
                            } catch {
                                AppLog.debug(
                                    "Could not remove directory \(fileName): \(error.localizedDescription) - may be in use or locked"
                                )
                                // Don't throw error, just log and continue
                            }
                        }
                    }
                }

                // Recursively clean subdirectories
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
                {
                    try await cleanupIncompleteFiles(in: item, for: modelId)
                }
            }
        } catch {
            AppLog.error(
                "Error cleaning cache directory \(directory.path): \(error.localizedDescription)")
            throw MLXCacheError.cleanupFailed(error.localizedDescription)
        }
    }

    /// Clean up all incomplete files in a directory
    private func cleanupAllIncompleteFiles(in directory: URL) async throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for item in contents {
                let fileName = item.lastPathComponent

                // Remove any incomplete files
                if fileName.contains(".incomplete") || fileName.contains(".tmp") {
                    try fileManager.removeItem(at: item)
                    AppLog.debug("Removed incomplete/temp file: \(fileName)")
                    continue
                }

                // Recursively clean subdirectories
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
                {
                    try await cleanupAllIncompleteFiles(in: item)
                }
            }
        } catch {
            AppLog.error(
                "Error in full cleanup of \(directory.path): \(error.localizedDescription)")
            throw MLXCacheError.cleanupFailed(error.localizedDescription)
        }
    }

    /// Get cache directory name for a model configuration
    private func getCacheDirectoryName(for modelConfig: MLXModelConfiguration) -> String {
        // Use the preconfigured cache directory name from the model configuration
        // This ensures consistency with manual download script naming
        AppLog.debug("🔍 [CACHE DEBUG] Using cache directory name from config: \(modelConfig.cacheDirectoryName)")
        return modelConfig.cacheDirectoryName
    }

    /// Find the model directory for a given model configuration
    func findModelDirectory(in cacheDir: URL, for modelConfig: MLXModelConfiguration) async -> URL?
    {
        AppLog.debug(
            "🔍 [CACHE DEBUG] Finding model directory for ID: \(modelConfig.modelId) in \(cacheDir.path)"
        )

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: cacheDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            AppLog.debug("🔍 [CACHE DEBUG] Found \(contents.count) items in cache directory")

            let expectedCacheDir = getCacheDirectoryName(for: modelConfig)
            AppLog.debug("🔍 [CACHE DEBUG] Looking for cache directory: \(expectedCacheDir)")

            for item in contents {
                let fileName = item.lastPathComponent

                AppLog.debug(
                    "🔍 [CACHE DEBUG] Checking item: \(fileName) against expected: \(expectedCacheDir)"
                )

                // Check for exact Hugging Face cache directory name
                if fileName == expectedCacheDir {
                    AppLog.debug("🔍 [CACHE DEBUG] ✅ Found matching directory: \(fileName)")
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory)
                        && isDirectory.boolValue
                    {
                        // Look for snapshots directory (required for HuggingFace cache structure)
                        let snapshotsDir = item.appendingPathComponent("snapshots")
                        if fileManager.fileExists(atPath: snapshotsDir.path) {
                            AppLog.debug(
                                "🔍 [CACHE DEBUG] Found snapshots directory, looking for main snapshot"
                            )
                            // Look specifically for 'main' snapshot first (manual downloads use this)
                            let mainSnapshotDir = snapshotsDir.appendingPathComponent("main")
                            if fileManager.fileExists(atPath: mainSnapshotDir.path) {
                                AppLog.debug(
                                    "🔍 [CACHE DEBUG] ✅ Found main snapshot directory: \(mainSnapshotDir.path)"
                                )
                                return mainSnapshotDir
                            }
                            // Fallback to finding the latest snapshot
                            if let latestSnapshot = await findLatestSnapshot(in: snapshotsDir) {
                                AppLog.debug(
                                    "🔍 [CACHE DEBUG] ✅ Found latest snapshot: \(latestSnapshot.path)"
                                )
                                return latestSnapshot
                            }
                            AppLog.debug(
                                "🔍 [CACHE DEBUG] ❌ No valid snapshots found in snapshots directory"
                            )
                        } else {
                            AppLog.debug(
                                "🔍 [CACHE DEBUG] ❌ No snapshots directory found - this suggests incomplete/corrupted cache"
                            )
                        }
                        
                        // Don't return the base directory if no snapshots found - indicates incomplete download
                        AppLog.debug(
                            "🔍 [CACHE DEBUG] ❌ Skipping directory without valid snapshots: \(fileName)"
                        )
                    }
                }

                // Check for direct model directory (legacy support)
                if fileName == modelConfig.modelId {
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory)
                        && isDirectory.boolValue
                    {
                        AppLog.debug("🔍 [CACHE DEBUG] ✅ Found legacy model directory: \(fileName)")
                        return item
                    }
                }

                // Recursively search subdirectories (but avoid infinite recursion)
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory)
                    && isDirectory.boolValue && !fileName.hasPrefix(".")
                {
                    // Only recurse into relevant directories to avoid performance issues
                    if fileName.contains("models--") || fileName.contains("mlx") || fileName.contains("cache") {
                        if let found = await findModelDirectory(in: item, for: modelConfig) {
                            return found
                        }
                    }
                }
            }
        } catch {
            AppLog.error("Error searching for model directory: \(error.localizedDescription)")
        }

        return nil
    }

    /// Legacy method for backward compatibility - converts modelId to model config
    private func findModelDirectory(in cacheDir: URL, for modelId: String) async -> URL? {
        // Create a temporary model config for legacy support
        let legacyConfig = MLXModelConfiguration(
            name: "Legacy Model",
            modelId: modelId,
            huggingFaceRepo: modelId,
            cacheDirectoryName: getCacheDirNameFromModelId(modelId),
            estimatedSizeGB: 1.0,
            modelKey: modelId
        )
        return await findModelDirectory(in: cacheDir, for: legacyConfig)
    }

    /// Convert legacy model ID to cache directory name
    private func getCacheDirNameFromModelId(_ modelId: String) -> String {
        switch modelId {
        case "gemma3_2B_4bit":
            return "models--mlx-community--gemma-2-2b-it-4bit"
        case "gemma3_9B_4bit":
            return "models--mlx-community--gemma-2-9b-it-4bit"
        case "llama3_2_1B_4bit":
            return "models--mlx-community--Llama-3.2-1B-Instruct-4bit"
        case "llama3_2_3B_4bit":
            return "models--mlx-community--Llama-3.2-3B-Instruct-4bit"
        default:
            return "models--" + modelId.replacingOccurrences(of: "/", with: "--")
        }
    }

    /// Find the latest snapshot in a snapshots directory
    private func findLatestSnapshot(in snapshotsDir: URL) async -> URL? {
        do {
            let snapshots = try fileManager.contentsOfDirectory(
                at: snapshotsDir,
                includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            let directories = snapshots.filter { url in
                var isDirectory: ObjCBool = false
                return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }

            // Return the most recently created directory
            return directories.max { url1, url2 in
                let date1 =
                    (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                    ?? Date.distantPast
                let date2 =
                    (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                    ?? Date.distantPast
                return date1 < date2
            }
        } catch {
            AppLog.error("Error finding latest snapshot: \(error.localizedDescription)")
            return nil
        }
    }

    /// Check if a file is incomplete or corrupted
    private func isFileIncompleteOrCorrupted(_ fileURL: URL) async -> Bool {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0

            // File is too small to be valid
            if fileSize < 10 {
                return true
            }

            // Check if file is a JSON file and can be parsed
            if fileURL.pathExtension == "json" {
                let data = try Data(contentsOf: fileURL)
                _ = try JSONSerialization.jsonObject(with: data)
            }

            return false
        } catch {
            AppLog.debug(
                "File validation failed for \(fileURL.lastPathComponent): \(error.localizedDescription)"
            )
            return true
        }
    }

    /// Check if a model directory is corrupted
    private func isModelDirectoryCorrupted(_ directory: URL) async -> Bool {
        let requiredFiles = ["config.json", "tokenizer.json"]

        for fileName in requiredFiles {
            let filePath = directory.appendingPathComponent(fileName)
            if !fileManager.fileExists(atPath: filePath.path) {
                return true
            }

            if await isFileIncompleteOrCorrupted(filePath) {
                return true
            }
        }

        return false
    }

    /// Analyze a cache directory for status information
    private func analyzeCacheDirectory(_ directory: URL) async -> (
        size: Int64, models: Int, corrupted: [String]
    ) {
        guard fileManager.fileExists(atPath: directory.path) else {
            return (0, 0, [])
        }

        // Use Task.detached to perform synchronous file enumeration in async context
        return await Task.detached { [fileManager] in
            var totalSize: Int64 = 0
            var modelCount = 0
            var corruptedFiles: [String] = []

            func processDirectory(_ dirURL: URL) {
                do {
                    let contents = try fileManager.contentsOfDirectory(
                        at: dirURL,
                        includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                        options: []
                    )

                    for fileURL in contents {
                        do {
                            let resourceValues = try fileURL.resourceValues(forKeys: [
                                .fileSizeKey, .isDirectoryKey,
                            ])

                            if let fileSize = resourceValues.fileSize {
                                totalSize += Int64(fileSize)
                            }

                            if resourceValues.isDirectory == true {
                                // Recursively process subdirectories
                                processDirectory(fileURL)
                            } else {
                                let fileName = fileURL.lastPathComponent

                                if fileName.contains(".incomplete") || fileName.contains(".tmp") {
                                    corruptedFiles.append(fileURL.path)
                                } else if fileName == "config.json" {
                                    modelCount += 1
                                }
                            }
                        } catch {
                            // Continue on error for individual files
                        }
                    }
                } catch {
                    // Continue on error for directory access
                }
            }

            processDirectory(directory)
            return (totalSize, modelCount, corruptedFiles)
        }.value
    }
}

// MARK: - Supporting Types

struct CacheStatus {
    let totalSizeBytes: Int64
    let modelCount: Int
    let corruptedFiles: [String]
    let cacheDirectories: [String]

    var totalSizeGB: Double {
        return Double(totalSizeBytes) / (1024 * 1024 * 1024)
    }

    var formattedSize: String {
        if totalSizeGB >= 1.0 {
            return String(format: "%.1f GB", totalSizeGB)
        } else {
            let totalSizeMB = Double(totalSizeBytes) / (1024 * 1024)
            return String(format: "%.0f MB", totalSizeMB)
        }
    }
}

enum MLXCacheError: LocalizedError {
    case cleanupFailed(String)
    case validationFailed(String)
    case directoryNotFound(String)

    var errorDescription: String? {
        switch self {
        case .cleanupFailed(let message):
            return "Cache cleanup failed: \(message)"
        case .validationFailed(let message):
            return "Cache validation failed: \(message)"
        case .directoryNotFound(let path):
            return "Cache directory not found: \(path)"
        }
    }
}
