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
        #if DEBUG
            return UserDefaults.standard.bool(forKey: "App.VerboseLogs")
        #else
            return false  // Always disable verbose logging in release builds
        #endif
    }

    static var isMetalFilteringEnabled: Bool {
        UserDefaults.standard.bool(forKey: "App.SuppressMetalErrors")
    }

    static func debug(_ message: String) {
        guard isVerboseEnabled else { return }
        guard !shouldSuppressMessage(message) else { return }
        logger.debug("\(cleanMessageForProduction(message))")
    }

    static func info(_ message: String) {
        guard isVerboseEnabled else { return }
        guard !shouldSuppressMessage(message) else { return }
        logger.info("\(cleanMessageForProduction(message))")
    }

    static func warn(_ message: String) {
        guard !shouldSuppressMessage(message) else { return }
        logger.warning("\(cleanMessageForProduction(message))")
    }

    static func error(_ message: String) {
        guard !shouldSuppressMessage(message) else { return }
        logger.error("\(cleanMessageForProduction(message))")
    }
    
    /// Essential logging that shows in both dev and production (minimal, important messages only)
    static func essential(_ message: String) {
        guard !shouldSuppressMessage(message) else { return }
        logger.info("\(cleanMessageForProduction(message))")
    }

    // MARK: - Message Cleaning
    
    /// Cleans messages for production by removing emojis and verbose debug markers in release builds
    private static func cleanMessageForProduction(_ message: String) -> String {
        #if DEBUG
            return message  // Keep all formatting in debug builds
        #else
            // Remove emojis and debug markers in release builds
            let cleanedMessage = message
                .replacingOccurrences(of: #"[🚀🔥🔍🛡️✅❌⚠️🖥️📡🆕💾🏁🔓🔄🚫]"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\[.*?\]"#, with: "", options: .regularExpression)  // Remove debug tags like [INIT AI]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            return cleanedMessage.isEmpty ? message : cleanedMessage  // Fallback if cleaning removes everything
        #endif
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
            "WebKit::WebFramePolicyListenerProxy::ignore",
            "Unable to create bundle at URL ((null))",
            "AFIsDeviceGreymatterEligible Missing entitlements",
            "nw_path_necp_check_for_updates Failed to copy updated result",
            "Unable to hide query parameters from script (missing data)",
            "Unable to obtain a task name port right for pid",
            "Failed to change to usage state",
            "WKErrorDomain Code=7",
            "Failed to load content rules",
            "Rule list lookup failed",
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
        logger.info("\(cleanMessageForProduction("🔧 [Metal] \(message)"))")
    }

    /// Logs a Metal warning that bypasses filtering
    static func metalWarn(_ message: String) {
        logger.warning("\(cleanMessageForProduction("⚠️ [Metal] \(message)"))")
    }
}
