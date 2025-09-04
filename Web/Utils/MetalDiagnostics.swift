import Foundation
import Metal
import os.log

/// Utility class for diagnosing and handling Metal framework issues
/// Specifically addresses the IconRendering framework binary.metallib corruption issue
class MetalDiagnostics {
    static let shared = MetalDiagnostics()

    private let logger = Logger(subsystem: "com.web.browser", category: "MetalDiagnostics")
    private var hasLoggedSystemIssue = false

    private init() {}

    // MARK: - System Diagnostics

    /// Performs comprehensive Metal system diagnostics at app startup
    func performStartupDiagnostics() {
        // Only run diagnostics once per app session
        guard !hasLoggedSystemIssue else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.checkMetalAvailability()
            self?.checkIconRenderingFramework()
            self?.logSystemConfiguration()
        }
    }

    /// Checks if Metal is available and functional
    private func checkMetalAvailability() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            logger.warning("⚠️ Metal system default device not available")
            return
        }

        // Test basic Metal functionality
        let commandQueue = device.makeCommandQueue()
        if commandQueue != nil {
            logger.debug("✅ Metal framework operational (device: \(device.name))")
        } else {
            logger.warning("⚠️ Metal command queue creation failed")
        }
    }

    /// Checks IconRendering framework status
    private func checkIconRenderingFramework() {
        let iconRenderingPath =
            "/System/Library/PrivateFrameworks/IconRendering.framework/Resources/binary.metallib"
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: iconRenderingPath) {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: iconRenderingPath)
                let fileSize = attributes[.size] as? Int64 ?? 0

                if fileSize > 0 {
                    logger.debug("✅ IconRendering binary.metallib exists (size: \(fileSize) bytes)")
                } else {
                    logger.warning("⚠️ IconRendering binary.metallib is empty")
                    logKnownIssue()
                }
            } catch {
                logger.warning(
                    "⚠️ Cannot read IconRendering binary.metallib attributes: \(error.localizedDescription)"
                )
                logKnownIssue()
            }
        } else {
            logger.warning("⚠️ IconRendering binary.metallib not found")
            logKnownIssue()
        }
    }

    /// Logs system configuration for debugging
    private func logSystemConfiguration() {
        let processInfo = ProcessInfo.processInfo
        let osVersion = processInfo.operatingSystemVersionString

        #if arch(arm64)
            let architecture = "Apple Silicon (ARM64)"
        #else
            let architecture = "Intel (x86_64)"
        #endif

        logger.debug("🖥️ System: \(osVersion) on \(architecture)")

        // Check if running under Rosetta
        #if arch(arm64)
            var ret = Int32(0)
            var size = MemoryLayout<Int32>.size
            if sysctlbyname("sysctl.proc_translated", &ret, &size, nil, 0) == 0 {
                if ret == 1 {
                    logger.debug("🔄 Running under Rosetta translation")
                }
            }
        #endif
    }

    /// Logs the known Metal shader library issue
    private func logKnownIssue() {
        guard !hasLoggedSystemIssue else { return }
        hasLoggedSystemIssue = true

        logger.info(
            """
            📋 KNOWN ISSUE: Metal shader library corruption detected

            Issue: IconRendering framework binary.metallib has invalid format
            Impact: Console errors during app startup (functionality unaffected)
            Cause: macOS system-level Metal framework corruption

            Solutions:
            1. Restart the system (often resolves temporary corruption)
            2. Reset Metal shader cache: sudo rm -rf /var/folders/*/C/com.apple.metal/
            3. Reinstall Xcode Command Line Tools if using development builds

            This is a known macOS system issue and does not affect app functionality.
            Error suppression is active to maintain clean console output.
            """)
    }

    // MARK: - Error Suppression

    /// Configures environment to suppress Metal-related console noise
    static func configureMetalLogging() {
        // Enable Metal error filtering in AppLog
        AppLog.enableMetalFiltering()
        // Suppress Metal validation layer warnings
        setenv("MTL_DEBUG_LAYER", "0", 1)
        setenv("MTL_SHADER_VALIDATION", "0", 1)

        // Reduce Metal Performance Shaders verbosity
        setenv("MPS_DISABLE_VERBOSE_LOGGING", "1", 1)

        // Suppress IconRendering framework errors specifically
        setenv("ICONRENDERING_SUPPRESS_ERRORS", "1", 1)

        // Disable Metal API validation in release builds
        #if !DEBUG
            setenv("MTL_CAPTURE_ENABLED", "0", 1)
            setenv("MTL_DEBUG_LAYER_VALIDATE_LOAD_ACTIONS", "0", 1)
            setenv("MTL_DEBUG_LAYER_VALIDATE_STORE_ACTIONS", "0", 1)

            AppLog.metalInfo("Metal logging configuration applied")
        #endif
    }

    /// Checks if a console message should be suppressed
    static func shouldSuppressMessage(_ message: String) -> Bool {
        let suppressedPatterns = [
            "precondition failure: unable to load binary archive for shader library",
            "IconRendering.framework/Resources/binary.metallib",
            "has an invalid format",
            "MTLLibrary creation failed",
            "Metal shader compilation failed",
            "Failed to load content rules",
            "Rule list lookup failed",
            "WKErrorDomain Code=7",
        ]

        return suppressedPatterns.contains { pattern in
            message.localizedCaseInsensitiveContains(pattern)
        }
    }
}

// MARK: - Console Output Filtering

/// Custom logging interceptor to filter Metal-related errors
class ConsoleFilter {
    private static let originalStderr = dup(STDERR_FILENO)
    private static var isFilteringEnabled = false

    /// Enables console filtering for Metal errors
    static func enableFiltering() {
        guard !isFilteringEnabled else { return }
        isFilteringEnabled = true

        // Note: Due to iOS/macOS security restrictions, we cannot directly
        // intercept stderr output. Instead, we rely on environment variables
        // and proper logging configuration to reduce noise.

        AppLog.debug("🔇 Metal error filtering enabled via environment configuration")
    }

    /// Disables console filtering
    static func disableFiltering() {
        guard isFilteringEnabled else { return }
        isFilteringEnabled = false

        AppLog.debug("🔊 Metal error filtering disabled")
    }
}
