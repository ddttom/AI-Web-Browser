import Foundation
import OSLog

/// Central logging gate to suppress verbose/noisy logs in production.
/// Toggle at runtime via UserDefaults key "App.VerboseLogs" (Bool).
/// Defaults to false. Enable temporarily by running:
///   defaults write com.example.Web App.VerboseLogs -bool YES
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.example.Web"
    private static let logger = Logger(subsystem: subsystem, category: "app")

    static var isVerboseEnabled: Bool {
        UserDefaults.standard.bool(forKey: "App.VerboseLogs")
    }

    static var isMetalFilteringEnabled: Bool {
        UserDefaults.standard.bool(forKey: "App.SuppressMetalErrors")
    }

    static func debug(_ message: String) {
        guard isVerboseEnabled else { return }
        guard !shouldSuppressMessage(message) else { return }
        logger.debug("\(message)")
    }

    static func info(_ message: String) {
        guard isVerboseEnabled else { return }
        guard !shouldSuppressMessage(message) else { return }
        logger.info("\(message)")
    }

    static func warn(_ message: String) {
        guard !shouldSuppressMessage(message) else { return }
        logger.warning("\(message)")
    }

    static func error(_ message: String) {
        guard !shouldSuppressMessage(message) else { return }
        logger.error("\(message)")
    }

    // MARK: - Metal Error Filtering

    /// Checks if a log message should be suppressed based on Metal error patterns
    private static func shouldSuppressMessage(_ message: String) -> Bool {
        // Only filter if Metal filtering is enabled or in release builds
        #if DEBUG
            guard isMetalFilteringEnabled else { return false }
        #endif

        let suppressedPatterns = [
            "precondition failure: unable to load binary archive for shader library",
            "IconRendering.framework/Resources/binary.metallib",
            "has an invalid format",
            "MTLLibrary creation failed",
            "Metal shader compilation failed",
            "binary.metallib",
            "IconRendering framework",
            "Metal device creation failed",
            "MTLCreateSystemDefaultDevice",
        ]

        return suppressedPatterns.contains { pattern in
            message.localizedCaseInsensitiveContains(pattern)
        }
    }

    /// Enables Metal error filtering
    static func enableMetalFiltering() {
        UserDefaults.standard.set(true, forKey: "App.SuppressMetalErrors")
        debug("🔇 Metal error filtering enabled")
    }

    /// Disables Metal error filtering
    static func disableMetalFiltering() {
        UserDefaults.standard.set(false, forKey: "App.SuppressMetalErrors")
        debug("🔊 Metal error filtering disabled")
    }

    /// Logs a Metal-related message with special handling
    static func metalInfo(_ message: String) {
        // Always log Metal diagnostic info, even when filtering is enabled
        logger.info("🔧 [Metal] \(message)")
    }

    /// Logs a Metal warning that bypasses filtering
    static func metalWarn(_ message: String) {
        logger.warning("⚠️ [Metal] \(message)")
    }
}
