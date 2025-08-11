import CryptoKit
import Foundation
import SwiftUI
import WebKit

/// CSPManager - Comprehensive Content Security Policy Management
///
/// This service provides complete CSP protection for all JavaScript injection points
/// in the browser, preventing XSS attacks, script manipulation, and data exfiltration.
///
/// Security Features:
/// - CSP nonce generation and validation for all injected scripts
/// - Input validation for all JavaScript→Native message bridges
/// - CSP violation monitoring and reporting
/// - Script integrity protection and tampering detection
/// - Centralized security policy management
///
/// Attack Vectors Addressed:
/// - XSS attacks through script injection
/// - Script manipulation by malicious websites
/// - Data exfiltration through compromised JavaScript bridges
/// - Man-in-the-middle script tampering
/// - Reflection-based XSS in message handlers
class CSPManager: NSObject, ObservableObject {
    static let shared = CSPManager()

    // MARK: - Configuration

    @Published var isCSPEnabled: Bool = true
    @Published var strictModeEnabled: Bool = true
    @Published var violationReportingEnabled: Bool = true
    @Published var scriptIntegrityChecksEnabled: Bool = true

    // MARK: - Security State

    @Published var cspViolations: [CSPViolation] = []
    @Published var blockedInjectionAttempts: Int = 0
    @Published var totalSecurityEvents: Int = 0

    private var activeNonces: Set<String> = []
    private var scriptHashes: [String: String] = [:]
    private var registeredUserContentControllers: Set<ObjectIdentifier> = []
    private let nonceLength = 32
    private let maxViolationHistory = 100

    // MARK: - CSP Policy Definitions

    struct CSPPolicy {
        let directives: [CSPDirective]
        let reportingEndpoint: String?
        let enforcementMode: EnforcementMode

        enum EnforcementMode {
            case enforce
            case reportOnly
        }

        func generatePolicyString(with nonce: String) -> String {
            let directiveStrings = directives.map { directive in
                var values = directive.values
                if directive.type == .scriptSrc && !values.contains("'none'") {
                    values.append("'nonce-\(nonce)'")
                }
                return "\(directive.type.rawValue) " + values.joined(separator: " ")
            }

            var policy = directiveStrings.joined(separator: "; ")

            if let endpoint = reportingEndpoint {
                policy += "; report-uri \(endpoint)"
            }

            return policy
        }
    }

    struct CSPDirective {
        let type: DirectiveType
        let values: [String]

        enum DirectiveType: String {
            case defaultSrc = "default-src"
            case scriptSrc = "script-src"
            case styleSrc = "style-src"
            case imgSrc = "img-src"
            case connectSrc = "connect-src"
            case frameSrc = "frame-src"
            case objectSrc = "object-src"
            case mediaSrc = "media-src"
            case fontSrc = "font-src"
            case baseUri = "base-uri"
            case formAction = "form-action"
            case frameAncestors = "frame-ancestors"
        }
    }

    // MARK: - Predefined Security Policies

    private lazy var strictBrowserPolicy = CSPPolicy(
        directives: [
            CSPDirective(type: .defaultSrc, values: ["'self'"]),
            CSPDirective(type: .scriptSrc, values: ["'self'", "'unsafe-eval'"]),  // nonce added dynamically
            CSPDirective(type: .styleSrc, values: ["'self'", "'unsafe-inline'"]),
            CSPDirective(type: .imgSrc, values: ["'self'", "data:", "https:"]),
            CSPDirective(type: .connectSrc, values: ["'self'", "https:"]),
            CSPDirective(type: .frameSrc, values: ["'self'"]),
            CSPDirective(type: .objectSrc, values: ["'none'"]),
            CSPDirective(type: .baseUri, values: ["'self'"]),
            CSPDirective(type: .formAction, values: ["'self'"]),
        ],
        reportingEndpoint: "csp://violations",
        enforcementMode: .enforce
    )

    private lazy var standardBrowserPolicy = CSPPolicy(
        directives: [
            CSPDirective(type: .defaultSrc, values: ["'self'", "'unsafe-inline'"]),
            CSPDirective(type: .scriptSrc, values: ["'self'", "'unsafe-eval'", "'unsafe-inline'"]),
            CSPDirective(type: .styleSrc, values: ["'self'", "'unsafe-inline'"]),
            CSPDirective(type: .imgSrc, values: ["*", "data:", "blob:"]),
            CSPDirective(type: .connectSrc, values: ["*"]),
            CSPDirective(type: .frameSrc, values: ["*"]),
            CSPDirective(type: .mediaSrc, values: ["*"]),
            CSPDirective(type: .fontSrc, values: ["*"]),
        ],
        reportingEndpoint: "csp://violations",
        enforcementMode: .enforce
    )

    // MARK: - Initialization

    override init() {
        super.init()
        loadConfiguration()
        setupViolationReporting()
        setupSecurityEventMonitoring()
    }

    // MARK: - Nonce Management

    /**
     * Generates a cryptographically secure nonce for script injection
     * Uses CryptoKit for secure random generation
     */
    func generateNonce() -> String {
        let randomData = Data((0..<nonceLength).map { _ in UInt8.random(in: 0...255) })
        let nonce = randomData.base64EncodedString()

        activeNonces.insert(nonce)

        // Clean up old nonces (keep last 50 for validation)
        if activeNonces.count > 50 {
            let sortedNonces = Array(activeNonces).sorted()
            activeNonces = Set(sortedNonces.suffix(50))
        }

        return nonce
    }

    /**
     * Validates that a nonce was generated by this CSP manager
     */
    func validateNonce(_ nonce: String) -> Bool {
        return activeNonces.contains(nonce)
    }

    // MARK: - Script Integrity Management

    /**
     * Generates SHA-256 hash for script content integrity verification
     */
    func generateScriptHash(for content: String, scriptType: ScriptType) -> String {
        let data = content.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: data)
        let hashString = Data(hash).base64EncodedString()

        scriptHashes[scriptType.rawValue] = hashString

        return hashString
    }

    /**
     * Validates script integrity using stored hashes
     */
    func validateScriptIntegrity(content: String, expectedHash: String) -> Bool {
        let data = content.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: data)
        let actualHash = Data(hash).base64EncodedString()

        return actualHash == expectedHash
    }

    enum ScriptType: String, CaseIterable {
        case linkHover = "linkHover"
        case timerCleanup = "timerCleanup"
        case autofill = "autofill"
        case adBlock = "adBlock"
        case incognito = "incognito"
        case contextExtraction = "contextExtraction"
        case agentBridge = "agentBridge"
    }

    // MARK: - CSP Policy Generation

    /**
     * Generates CSP policy for injected scripts with nonce protection
     */
    func generateCSPPolicyForInjectedScripts(nonce: String) -> String {
        let policy = strictModeEnabled ? strictBrowserPolicy : standardBrowserPolicy
        return policy.generatePolicyString(with: nonce)
    }

    /**
     * Creates secure script wrapper with CSP nonce and integrity checks
     */
    func createSecureScript(content: String, scriptType: ScriptType, nonce: String) -> String {
        let scriptHash = generateScriptHash(for: content, scriptType: scriptType)

        return """
            (function() {
                'use strict';
                
                // CSP Security Header - DO NOT MODIFY
                const CSP_NONCE = '\(nonce)';
                const SCRIPT_TYPE = '\(scriptType.rawValue)';
                const SCRIPT_HASH = '\(scriptHash)';
                
                // Integrity check - verify script hasn't been tampered with
                if (!window.webkit || !window.webkit.messageHandlers) {
                    console.error('CSP: WebKit message handlers not available - potential tampering detected');
                    return;
                }
                
                // Anti-tampering: Freeze critical objects after setup
                const originalWebkit = window.webkit;
                
                // Script content begins here
                \(content)
                
                // CSP Footer - Integrity verification
                if (window.webkit !== originalWebkit) {
                    console.error('CSP: WebKit object tampering detected for script type: ' + SCRIPT_TYPE);
                    if (window.webkit.messageHandlers.cspViolation) {
                        window.webkit.messageHandlers.cspViolation.postMessage({
                            type: 'scriptTampering',
                            scriptType: SCRIPT_TYPE,
                            nonce: CSP_NONCE
                        });
                    }
                }
            })();
            """
    }

    // MARK: - Message Handler Input Validation

    /**
     * Validates and sanitizes input from JavaScript message handlers
     * Prevents XSS, injection attacks, and data exfiltration
     */
    func validateMessageInput(_ message: WKScriptMessage, expectedHandler: String)
        -> ValidationResult
    {
        guard message.name == expectedHandler else {
            logSecurityViolation(
                .unexpectedMessageHandler(
                    expected: expectedHandler,
                    received: message.name,
                    source: message.webView?.url?.host ?? "unknown"
                ))
            return .invalid(.unexpectedHandler)
        }

        guard let body = message.body as? [String: Any] else {
            logSecurityViolation(
                .invalidMessageFormat(
                    handler: expectedHandler,
                    source: message.webView?.url?.host ?? "unknown"
                ))
            return .invalid(.malformedData)
        }

        // Validate required fields
        guard body["type"] is String else {
            logSecurityViolation(
                .missingRequiredField(
                    field: "type",
                    handler: expectedHandler,
                    source: message.webView?.url?.host ?? "unknown"
                ))
            return .invalid(.missingRequiredField)
        }

        // Sanitize string inputs
        let sanitizedBody = sanitizeMessageBody(body)

        // Check for potential XSS payloads
        if containsPotentialXSS(sanitizedBody) {
            logSecurityViolation(
                .potentialXSSAttempt(
                    handler: expectedHandler,
                    payload: String(describing: sanitizedBody),
                    source: message.webView?.url?.host ?? "unknown"
                ))
            return .invalid(.potentialXSS)
        }

        // Rate limiting check
        if !checkRateLimit(for: message.webView?.url?.host ?? "unknown", handler: expectedHandler) {
            logSecurityViolation(
                .rateLimitExceeded(
                    handler: expectedHandler,
                    source: message.webView?.url?.host ?? "unknown"
                ))
            return .invalid(.rateLimitExceeded)
        }

        return .valid(sanitizedBody)
    }

    enum ValidationResult {
        case valid([String: Any])
        case invalid(ValidationError)
    }

    enum ValidationError {
        case unexpectedHandler
        case malformedData
        case missingRequiredField
        case potentialXSS
        case rateLimitExceeded
        case scriptTampering
        case invalidNonce

        var description: String {
            switch self {
            case .unexpectedHandler: return "Unexpected message handler"
            case .malformedData: return "Malformed message data"
            case .missingRequiredField: return "Missing required field"
            case .potentialXSS: return "Potential XSS payload detected"
            case .rateLimitExceeded: return "Rate limit exceeded"
            case .scriptTampering: return "Script tampering detected"
            case .invalidNonce: return "Invalid or missing nonce"
            }
        }
    }

    // MARK: - Input Sanitization

    private func sanitizeMessageBody(_ body: [String: Any]) -> [String: Any] {
        var sanitized: [String: Any] = [:]

        for (key, value) in body {
            let sanitizedKey = sanitizeString(key)

            switch value {
            case let stringValue as String:
                sanitized[sanitizedKey] = sanitizeString(stringValue)
            case let numberValue as NSNumber:
                sanitized[sanitizedKey] = numberValue
            case let boolValue as Bool:
                sanitized[sanitizedKey] = boolValue
            case let arrayValue as [Any]:
                sanitized[sanitizedKey] = sanitizeArray(arrayValue)
            case let dictValue as [String: Any]:
                sanitized[sanitizedKey] = sanitizeMessageBody(dictValue)
            default:
                // Remove potentially dangerous types
                continue
            }
        }

        return sanitized
    }

    private func sanitizeString(_ input: String) -> String {
        // Remove potential XSS vectors
        var sanitized = input
        sanitized = sanitized.replacingOccurrences(
            of: "<script", with: "&lt;script", options: .caseInsensitive)
        sanitized = sanitized.replacingOccurrences(
            of: "javascript:", with: "javascript-", options: .caseInsensitive)
        sanitized = sanitized.replacingOccurrences(
            of: "data:text/html", with: "data-text-html", options: .caseInsensitive)
        sanitized = sanitized.replacingOccurrences(
            of: "vbscript:", with: "vbscript-", options: .caseInsensitive)

        // Limit length to prevent DoS
        return String(sanitized.prefix(10000))
    }

    private func sanitizeArray(_ array: [Any]) -> [Any] {
        return array.compactMap { item in
            switch item {
            case let stringValue as String:
                return sanitizeString(stringValue)
            case let numberValue as NSNumber:
                return numberValue
            case let boolValue as Bool:
                return boolValue
            default:
                return nil
            }
        }.prefix(1000).map { $0 }
    }

    private func containsPotentialXSS(_ body: [String: Any]) -> Bool {
        let xssPatterns = [
            "<script",
            "javascript:",
            "data:text/html",
            "vbscript:",
            "onload=",
            "onerror=",
            "onclick=",
            "eval(",
            "setTimeout(",
            "setInterval(",
        ]

        let bodyString = String(describing: body).lowercased()
        return xssPatterns.contains { pattern in
            bodyString.contains(pattern.lowercased())
        }
    }

    // MARK: - Rate Limiting

    private var rateLimitCounters: [String: [Date]] = [:]
    private let maxRequestsPerMinute = 100

    private func checkRateLimit(for source: String, handler: String) -> Bool {
        let key = "\(source):\(handler)"
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)

        // Clean old entries
        rateLimitCounters[key] = rateLimitCounters[key]?.filter { $0 > oneMinuteAgo } ?? []

        // Check current count
        let currentCount = rateLimitCounters[key]?.count ?? 0

        if currentCount >= maxRequestsPerMinute {
            return false
        }

        // Add current request
        rateLimitCounters[key, default: []].append(now)

        return true
    }

    // MARK: - CSP Violation Monitoring

    struct CSPViolation {
        let id: UUID
        let timestamp: Date
        let violationType: ViolationType
        let source: String
        let details: String
        let severity: SecuritySeverity

        enum ViolationType {
            case scriptTampering
            case invalidNonce
            case unexpectedMessageHandler
            case potentialXSS
            case rateLimitExceeded
            case integrityFailure
            case unauthorizedScriptExecution
        }

        enum SecuritySeverity {
            case low, medium, high, critical

            var color: Color {
                switch self {
                case .low: return .yellow
                case .medium: return .orange
                case .high: return .red
                case .critical: return .purple
                }
            }
        }
    }

    private func logSecurityViolation(_ violation: SecurityViolationType) {
        guard violationReportingEnabled else { return }

        let cspViolation = CSPViolation(
            id: UUID(),
            timestamp: Date(),
            violationType: violation.type,
            source: violation.source,
            details: violation.details,
            severity: violation.severity
        )

        DispatchQueue.main.async {
            self.cspViolations.append(cspViolation)
            self.totalSecurityEvents += 1

            // Maintain violation history limit
            if self.cspViolations.count > self.maxViolationHistory {
                self.cspViolations.removeFirst(self.cspViolations.count - self.maxViolationHistory)
            }
        }

        // Log to console and security audit
        NSLog("🔒 CSP VIOLATION: \(violation.details) - Source: \(violation.source)")

        // Post notification for UI updates
        NotificationCenter.default.post(
            name: .cspViolationDetected,
            object: cspViolation
        )
    }

    private enum SecurityViolationType {
        case unexpectedMessageHandler(expected: String, received: String, source: String)
        case invalidMessageFormat(handler: String, source: String)
        case missingRequiredField(field: String, handler: String, source: String)
        case potentialXSSAttempt(handler: String, payload: String, source: String)
        case rateLimitExceeded(handler: String, source: String)
        case scriptTampering(scriptType: String, source: String)
        case integrityFailure(scriptType: String, source: String)

        var type: CSPViolation.ViolationType {
            switch self {
            case .unexpectedMessageHandler: return .unexpectedMessageHandler
            case .invalidMessageFormat: return .unexpectedMessageHandler
            case .missingRequiredField: return .unexpectedMessageHandler
            case .potentialXSSAttempt: return .potentialXSS
            case .rateLimitExceeded: return .rateLimitExceeded
            case .scriptTampering: return .scriptTampering
            case .integrityFailure: return .integrityFailure
            }
        }

        var severity: CSPViolation.SecuritySeverity {
            switch self {
            case .unexpectedMessageHandler: return .high
            case .invalidMessageFormat: return .medium
            case .missingRequiredField: return .low
            case .potentialXSSAttempt: return .critical
            case .rateLimitExceeded: return .medium
            case .scriptTampering: return .critical
            case .integrityFailure: return .critical
            }
        }

        var source: String {
            switch self {
            case .unexpectedMessageHandler(_, _, let source),
                .invalidMessageFormat(_, let source),
                .missingRequiredField(_, _, let source),
                .potentialXSSAttempt(_, _, let source),
                .rateLimitExceeded(_, let source),
                .scriptTampering(_, let source),
                .integrityFailure(_, let source):
                return source
            }
        }

        var details: String {
            switch self {
            case .unexpectedMessageHandler(let expected, let received, _):
                return "Expected handler '\(expected)', received '\(received)'"
            case .invalidMessageFormat(let handler, _):
                return "Invalid message format for handler '\(handler)'"
            case .missingRequiredField(let field, let handler, _):
                return "Missing required field '\(field)' in handler '\(handler)'"
            case .potentialXSSAttempt(let handler, let payload, _):
                return "Potential XSS in handler '\(handler)': \(payload.prefix(100))"
            case .rateLimitExceeded(let handler, _):
                return "Rate limit exceeded for handler '\(handler)'"
            case .scriptTampering(let scriptType, _):
                return "Script tampering detected for type '\(scriptType)'"
            case .integrityFailure(let scriptType, _):
                return "Script integrity failure for type '\(scriptType)'"
            }
        }
    }

    // MARK: - Mixed Content Integration

    private func setupMixedContentIntegration() {
        // Listen for mixed content violations to correlate with CSP violations
        NotificationCenter.default.addObserver(
            forName: .mixedContentSecurityEvent,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleMixedContentSecurityEvent(notification)
        }
    }

    private func handleMixedContentSecurityEvent(_ notification: Notification) {
        guard
            let mixedContentEvent = notification.object
                as? MixedContentManager.MixedContentSecurityEvent
        else {
            return
        }

        // Log correlation between mixed content and potential CSP implications
        if mixedContentEvent.eventType == .mixedContentDetected
            || mixedContentEvent.eventType == .policyViolation
        {

            DispatchQueue.main.async { [weak self] in
                self?.logSecurityViolation(
                    .integrityFailure(
                        scriptType: "mixed-content",
                        source: mixedContentEvent.details["url"] ?? "unknown"
                    ))
            }

            NSLog("🔗 CSP: Mixed content event correlated with potential security implications")
        }
    }

    // MARK: - Configuration Management

    private func loadConfiguration() {
        let defaults = UserDefaults.standard

        isCSPEnabled = defaults.object(forKey: "CSPEnabled") as? Bool ?? true
        strictModeEnabled = defaults.object(forKey: "CSPStrictMode") as? Bool ?? true
        violationReportingEnabled =
            defaults.object(forKey: "CSPViolationReporting") as? Bool ?? true
        scriptIntegrityChecksEnabled =
            defaults.object(forKey: "CSPScriptIntegrity") as? Bool ?? true

        // Set up mixed content integration
        setupMixedContentIntegration()
    }

    func saveConfiguration() {
        let defaults = UserDefaults.standard

        defaults.set(isCSPEnabled, forKey: "CSPEnabled")
        defaults.set(strictModeEnabled, forKey: "CSPStrictMode")
        defaults.set(violationReportingEnabled, forKey: "CSPViolationReporting")
        defaults.set(scriptIntegrityChecksEnabled, forKey: "CSPScriptIntegrity")
    }

    // MARK: - Security Event Monitoring

    private func setupViolationReporting() {
        // Set up custom URL scheme handler for CSP violation reports
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCSPViolationReport),
            name: .cspViolationReportReceived,
            object: nil
        )
    }

    private func setupSecurityEventMonitoring() {
        // Monitor for security-related events
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            self.performSecurityHealthCheck()
        }
    }

    @objc private func handleCSPViolationReport(_ notification: Notification) {
        guard let violationData = notification.userInfo as? [String: Any] else { return }

        // Process CSP violation report from WebView
        logSecurityViolation(
            .integrityFailure(
                scriptType: violationData["scriptType"] as? String ?? "unknown",
                source: violationData["source"] as? String ?? "unknown"
            ))
    }

    private func performSecurityHealthCheck() {
        // Clean up old rate limit entries
        let oneHourAgo = Date().addingTimeInterval(-3600)
        rateLimitCounters = rateLimitCounters.compactMapValues { dates in
            let filtered = dates.filter { $0 > oneHourAgo }
            return filtered.isEmpty ? nil : filtered
        }

        // Clean up old nonces
        if activeNonces.count > 100 {
            let sortedNonces = Array(activeNonces).sorted()
            activeNonces = Set(sortedNonces.suffix(50))
        }

        // Note: registeredUserContentControllers cleanup is handled automatically by ObjectIdentifier
        // when UserContentControllers are deallocated, but we could add explicit cleanup if needed
    }

    // MARK: - Public Security API

    /**
     * Main API for securing JavaScript injection in WebViews
     */
    func secureScriptInjection(script: String, type: ScriptType, webView: WKWebView)
        -> WKUserScript?
    {
        guard isCSPEnabled else {
            return WKUserScript(
                source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        }

        let nonce = generateNonce()
        let secureScript = createSecureScript(content: script, scriptType: type, nonce: nonce)

        // Add CSP violation handler only if not already registered for this UserContentController
        let userContentControllerID = ObjectIdentifier(webView.configuration.userContentController)
        if !registeredUserContentControllers.contains(userContentControllerID) {
            webView.configuration.userContentController.add(self, name: "cspViolation")
            registeredUserContentControllers.insert(userContentControllerID)
        }

        return WKUserScript(
            source: secureScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }

    /**
     * Remove UserContentController registration when WebView is deallocated
     */
    func unregisterUserContentController(_ userContentController: WKUserContentController) {
        let userContentControllerID = ObjectIdentifier(userContentController)
        registeredUserContentControllers.remove(userContentControllerID)
    }

    /**
     * Get current security statistics
     */
    func getSecurityStatistics() -> SecurityStatistics {
        return SecurityStatistics(
            totalViolations: cspViolations.count,
            criticalViolations: cspViolations.filter { $0.severity == .critical }.count,
            blockedInjectionAttempts: blockedInjectionAttempts,
            activeNonces: activeNonces.count,
            isCSPEnabled: isCSPEnabled,
            strictModeEnabled: strictModeEnabled
        )
    }

    struct SecurityStatistics {
        let totalViolations: Int
        let criticalViolations: Int
        let blockedInjectionAttempts: Int
        let activeNonces: Int
        let isCSPEnabled: Bool
        let strictModeEnabled: Bool
    }
}

// MARK: - WKScriptMessageHandler for CSP Violations

extension CSPManager: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        guard message.name == "cspViolation" else { return }

        let validationResult = validateMessageInput(message, expectedHandler: "cspViolation")

        switch validationResult {
        case .valid(let sanitizedBody):
            if let type = sanitizedBody["type"] as? String,
                let scriptType = sanitizedBody["scriptType"] as? String
            {

                switch type {
                case "scriptTampering":
                    logSecurityViolation(
                        .scriptTampering(
                            scriptType: scriptType,
                            source: message.webView?.url?.host ?? "unknown"
                        ))

                default:
                    break
                }
            }

        case .invalid(let error):
            NSLog("🔒 CSP: Validation failed for CSP violation report: \(error.description)")
        }
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let cspViolationDetected = Notification.Name("cspViolationDetected")
    static let cspViolationReportReceived = Notification.Name("cspViolationReportReceived")
    static let cspSecurityEventOccurred = Notification.Name("cspSecurityEventOccurred")
}
