import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// TokenManager: Secure JWT/OAuth token storage and lifecycle management
///
/// This service provides comprehensive token management for browser-level authentication,
/// sync services, and secure token storage. It leverages the same security patterns as
/// PasswordManager.swift with dedicated token-specific functionality.
///
/// Security Features:
/// - AES-256-GCM encryption for sensitive tokens (refresh tokens, client secrets)
/// - Keychain integration with biometric authentication
/// - Token lifecycle management (refresh, expiration, revocation)
/// - Secure token validation and cleanup
/// - Comprehensive security logging for audit trails
@MainActor
class TokenManager: NSObject, ObservableObject {
    static let shared = TokenManager()

    // MARK: - Published Properties
    @Published var isTokenAuthEnabled: Bool = true
    @Published var requireBiometricAuth: Bool = true
    @Published var activeTokens: [StoredToken] = []
    @Published var tokenSessions: [TokenSession] = []

    // MARK: - Private Properties
    private let tokenServiceName = "com.web.browser.tokens"
    private let sessionServiceName = "com.web.browser.sessions"
    private var encryptionKey: SymmetricKey?
    private let context = LAContext()

    // MARK: - Data Models

    /// Represents a stored authentication token with metadata
    struct StoredToken: Identifiable, Codable, Sendable {
        let id: UUID
        let tokenType: TokenType
        let provider: AuthProvider
        let identifier: String  // email, username, or service identifier
        let encryptedAccessToken: Data?
        let encryptedRefreshToken: Data?
        let scope: String?
        let expiresAt: Date?
        let refreshExpiresAt: Date?
        let dateCreated: Date
        let lastUsed: Date
        let lastRefreshed: Date?

        enum TokenType: String, Codable, CaseIterable {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
            case bearerToken = "bearer_token"
            case apiKey = "api_key"

            var displayName: String {
                switch self {
                case .accessToken: return "Access Token"
                case .refreshToken: return "Refresh Token"
                case .idToken: return "ID Token"
                case .bearerToken: return "Bearer Token"
                case .apiKey: return "API Key"
                }
            }
        }

        enum AuthProvider: String, Codable, CaseIterable {
            case browserSync = "browser_sync"
            case cloudSync = "cloud_sync"
            case customAPI = "custom_api"
            case oauthProvider = "oauth_provider"
            case enterpriseSSO = "enterprise_sso"

            var displayName: String {
                switch self {
                case .browserSync: return "Browser Sync"
                case .cloudSync: return "Cloud Sync"
                case .customAPI: return "Custom API"
                case .oauthProvider: return "OAuth Provider"
                case .enterpriseSSO: return "Enterprise SSO"
                }
            }
        }

        var isExpired: Bool {
            guard let expiresAt = expiresAt else { return false }
            return Date() >= expiresAt
        }

        var needsRefresh: Bool {
            guard let expiresAt = expiresAt else { return false }
            // Refresh if token expires within 5 minutes
            return Date().addingTimeInterval(300) >= expiresAt
        }

        var canRefresh: Bool {
            guard let refreshExpiresAt = refreshExpiresAt else {
                return encryptedRefreshToken != nil
            }
            return Date() < refreshExpiresAt && encryptedRefreshToken != nil
        }
    }

    /// Represents an active authentication session
    struct TokenSession: Identifiable, Codable, Sendable {
        let id: UUID
        let provider: StoredToken.AuthProvider
        let identifier: String
        let sessionToken: String  // Hashed session identifier
        let tokenIds: [UUID]  // Associated token IDs
        let createdAt: Date
        let lastAccessedAt: Date
        let expiresAt: Date?
        let deviceInfo: DeviceInfo

        struct DeviceInfo: Codable {
            let deviceName: String
            let osVersion: String
            let appVersion: String
            let sessionFingerprint: String  // Cryptographic fingerprint
        }

        var isExpired: Bool {
            guard let expiresAt = expiresAt else { return false }
            return Date() >= expiresAt
        }
    }

    // MARK: - Settings Model
    struct TokenManagerSettings: Codable {
        let isTokenAuthEnabled: Bool
        let requireBiometricAuth: Bool
        let autoRefreshTokens: Bool
        let tokenCleanupInterval: TimeInterval
        let maxTokenAge: TimeInterval
        let enableSecurityLogging: Bool
    }

    // MARK: - Initialization
    override init() {
        // Initialize dependencies
        self.securityMonitor = SecurityMonitor.shared

        super.init()
        loadSettings()
        loadTokenMetadata()
        setupTokenCleanup()

        // Log initialization (security event)
        logSecurityEvent(
            .systemInit,
            details: [
                "service": "TokenManager",
                "biometric_required": requireBiometricAuth,
            ])
    }

    // MARK: - Encryption Key Management

    /// Retrieves or creates encryption key for token encryption
    /// Uses same pattern as PasswordManager for consistency
    private func getOrCreateEncryptionKey() -> SymmetricKey {
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(tokenServiceName).encryptionKey",
            kSecAttrAccount as String: "tokenMasterKey",
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(keyQuery as CFDictionary, &result)

        if status == errSecSuccess, let keyData = result as? Data {
            return SymmetricKey(data: keyData)
        } else {
            // Generate new 256-bit encryption key
            let newKey = SymmetricKey(size: .bits256)
            let keyData = newKey.withUnsafeBytes { Data($0) }

            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "\(tokenServiceName).encryptionKey",
                kSecAttrAccount as String: "tokenMasterKey",
                kSecValueData as String: keyData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ]

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

            if addStatus == errSecSuccess {
                logSecurityEvent(
                    .keyGeneration,
                    details: [
                        "key_type": "token_encryption",
                        "key_size": "256_bits",
                    ])
            } else {
                logSecurityEvent(
                    .keyGenerationFailed,
                    details: [
                        "error": SecCopyErrorMessageString(addStatus, nil) as String? ?? "Unknown"
                    ])
            }

            return newKey
        }
    }

    // MARK: - Token Storage and Retrieval

    /// Stores a token securely in the Keychain with encryption
    func storeToken(
        tokenType: StoredToken.TokenType,
        provider: StoredToken.AuthProvider,
        identifier: String,
        accessToken: String?,
        refreshToken: String?,
        scope: String? = nil,
        expiresIn: TimeInterval? = nil,
        refreshExpiresIn: TimeInterval? = nil
    ) async -> Bool {

        guard await authenticateUser() else {
            logSecurityEvent(
                .authenticationFailed,
                details: [
                    "operation": "store_token",
                    "provider": provider.rawValue,
                ])
            return false
        }

        do {
            // Lazy initialization of encryption key
            if encryptionKey == nil {
                encryptionKey = getOrCreateEncryptionKey()
            }

            let now = Date()
            let expiresAt = expiresIn.map { now.addingTimeInterval($0) }
            let refreshExpiresAt = refreshExpiresIn.map { now.addingTimeInterval($0) }

            // Encrypt sensitive tokens
            let encryptedAccessToken = try accessToken.map { try encryptToken($0) }
            let encryptedRefreshToken = try refreshToken.map { try encryptToken($0) }

            let storedToken = StoredToken(
                id: UUID(),
                tokenType: tokenType,
                provider: provider,
                identifier: identifier,
                encryptedAccessToken: encryptedAccessToken,
                encryptedRefreshToken: encryptedRefreshToken,
                scope: scope,
                expiresAt: expiresAt,
                refreshExpiresAt: refreshExpiresAt,
                dateCreated: now,
                lastUsed: now,
                lastRefreshed: nil
            )

            // Store in Keychain
            let account = "\(provider.rawValue):\(identifier)"
            let tokenData = try JSONEncoder().encode(storedToken)

            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: tokenServiceName,
                kSecAttrAccount as String: account,
                kSecValueData as String: tokenData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ]

            // Delete existing token
            SecItemDelete(query as CFDictionary)

            // Add new token
            let status = SecItemAdd(query as CFDictionary, nil)

            if status == errSecSuccess {
                await MainActor.run {
                    // Remove existing token for same provider/identifier
                    activeTokens.removeAll {
                        $0.provider == provider && $0.identifier == identifier
                    }
                    activeTokens.append(storedToken)
                    activeTokens.sort { $0.lastUsed > $1.lastUsed }
                }

                saveTokenMetadata()

                logSecurityEvent(
                    .tokenStored,
                    details: [
                        "provider": provider.rawValue,
                        "token_type": tokenType.rawValue,
                        "has_refresh": refreshToken != nil,
                    ])

                return true
            } else {
                logSecurityEvent(
                    .tokenStorageFailed,
                    details: [
                        "provider": provider.rawValue,
                        "error": SecCopyErrorMessageString(status, nil) as String? ?? "Unknown",
                    ])
            }

        } catch {
            logSecurityEvent(
                .tokenEncryptionFailed,
                details: [
                    "provider": provider.rawValue,
                    "error": error.localizedDescription,
                ])
        }

        return false
    }

    /// Retrieves and decrypts a stored token
    func retrieveToken(
        provider: StoredToken.AuthProvider,
        identifier: String,
        tokenType: StoredToken.TokenType = .accessToken
    ) async -> String? {

        guard await authenticateUser() else {
            logSecurityEvent(
                .authenticationFailed,
                details: [
                    "operation": "retrieve_token",
                    "provider": provider.rawValue,
                ])
            return nil
        }

        let account = "\(provider.rawValue):\(identifier)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenServiceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess,
            let data = result as? Data,
            let storedToken = try? JSONDecoder().decode(StoredToken.self, from: data)
        {

            do {
                // Lazy initialization of encryption key
                if encryptionKey == nil {
                    encryptionKey = getOrCreateEncryptionKey()
                }

                let encryptedData: Data?
                switch tokenType {
                case .accessToken, .bearerToken, .idToken, .apiKey:
                    encryptedData = storedToken.encryptedAccessToken
                case .refreshToken:
                    encryptedData = storedToken.encryptedRefreshToken
                }

                guard let encrypted = encryptedData else {
                    logSecurityEvent(
                        .tokenNotFound,
                        details: [
                            "provider": provider.rawValue,
                            "token_type": tokenType.rawValue,
                        ])
                    return nil
                }

                let decryptedToken = try decryptToken(encrypted)

                // Update last used date
                await updateLastUsed(for: storedToken)

                logSecurityEvent(
                    .tokenRetrieved,
                    details: [
                        "provider": provider.rawValue,
                        "token_type": tokenType.rawValue,
                    ])

                return decryptedToken

            } catch {
                logSecurityEvent(
                    .tokenDecryptionFailed,
                    details: [
                        "provider": provider.rawValue,
                        "error": error.localizedDescription,
                    ])
            }
        } else {
            logSecurityEvent(
                .tokenNotFound,
                details: [
                    "provider": provider.rawValue,
                    "keychain_status": String(status),
                ])
        }

        return nil
    }

    /// Deletes a stored token
    func deleteToken(provider: StoredToken.AuthProvider, identifier: String) async -> Bool {
        guard await authenticateUser() else {
            logSecurityEvent(
                .authenticationFailed,
                details: [
                    "operation": "delete_token",
                    "provider": provider.rawValue,
                ])
            return false
        }

        let account = "\(provider.rawValue):\(identifier)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenServiceName,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess {
            await MainActor.run {
                activeTokens.removeAll { $0.provider == provider && $0.identifier == identifier }
            }

            saveTokenMetadata()

            logSecurityEvent(
                .tokenDeleted,
                details: [
                    "provider": provider.rawValue
                ])

            return true
        } else {
            logSecurityEvent(
                .tokenDeletionFailed,
                details: [
                    "provider": provider.rawValue,
                    "error": SecCopyErrorMessageString(status, nil) as String? ?? "Unknown",
                ])
        }

        return false
    }

    // MARK: - Token Lifecycle Management

    /// Refreshes an expired or expiring token
    func refreshToken(provider: StoredToken.AuthProvider, identifier: String) async -> Bool {
        guard
            let storedToken = activeTokens.first(where: {
                $0.provider == provider && $0.identifier == identifier
            }),
            storedToken.canRefresh
        else {

            logSecurityEvent(
                .tokenRefreshNotAvailable,
                details: [
                    "provider": provider.rawValue
                ])
            return false
        }

        // Get refresh token
        guard
            await retrieveToken(
                provider: provider, identifier: identifier, tokenType: .refreshToken) != nil
        else {
            logSecurityEvent(
                .refreshTokenNotFound,
                details: [
                    "provider": provider.rawValue
                ])
            return false
        }

        // This will be implemented by OAuthManager
        // For now, we log the refresh attempt
        logSecurityEvent(
            .tokenRefreshAttempted,
            details: [
                "provider": provider.rawValue
            ])

        // TODO: Integrate with OAuthManager for actual token refresh
        return false
    }

    /// Revokes a token (logs out)
    func revokeToken(provider: StoredToken.AuthProvider, identifier: String) async -> Bool {
        // First attempt to revoke token with provider (if supported)
        if await retrieveToken(provider: provider, identifier: identifier) != nil {
            // TODO: Integrate with OAuthManager for token revocation
            logSecurityEvent(
                .tokenRevocationAttempted,
                details: [
                    "provider": provider.rawValue
                ])
        }

        // Always delete local token regardless of revocation success
        let deleted = await deleteToken(provider: provider, identifier: identifier)

        if deleted {
            logSecurityEvent(
                .tokenRevoked,
                details: [
                    "provider": provider.rawValue
                ])
        }

        return deleted
    }

    /// Cleans up expired tokens
    func cleanupExpiredTokens() async {
        var cleanupCount = 0
        let expiredTokens = activeTokens.filter { $0.isExpired && !$0.canRefresh }

        for token in expiredTokens {
            if await deleteToken(provider: token.provider, identifier: token.identifier) {
                cleanupCount += 1
            }
        }

        if cleanupCount > 0 {
            logSecurityEvent(
                .expiredTokensCleanup,
                details: [
                    "cleanup_count": cleanupCount
                ])
        }
    }

    // MARK: - Authentication

    /// Authenticates user with biometrics if required
    private func authenticateUser() async -> Bool {
        guard requireBiometricAuth else { return true }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Authenticate to access stored tokens"
            ) { success, error in
                if let error = error {
                    Task { @MainActor in
                        self.logSecurityEvent(
                            .biometricAuthFailed,
                            details: [
                                "error": error.localizedDescription
                            ])
                    }
                }
                continuation.resume(returning: success)
            }
        }
    }

    // MARK: - Encryption/Decryption

    private func encryptToken(_ token: String) throws -> Data {
        if encryptionKey == nil {
            encryptionKey = getOrCreateEncryptionKey()
        }

        let tokenData = Data(token.utf8)
        let sealedBox = try AES.GCM.seal(tokenData, using: encryptionKey!)
        return sealedBox.combined!
    }

    private func decryptToken(_ encryptedData: Data) throws -> String {
        if encryptionKey == nil {
            encryptionKey = getOrCreateEncryptionKey()
        }

        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey!)
        return String(data: decryptedData, encoding: .utf8) ?? ""
    }

    // MARK: - Data Management

    private func loadTokenMetadata() {
        if let data = UserDefaults.standard.data(forKey: "tokenMetadata"),
            let metadata = try? JSONDecoder().decode([StoredToken].self, from: data)
        {
            activeTokens = metadata.sorted { $0.lastUsed > $1.lastUsed }
        }
    }

    private func saveTokenMetadata() {
        if let data = try? JSONEncoder().encode(activeTokens) {
            UserDefaults.standard.set(data, forKey: "tokenMetadata")
        }
    }

    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "tokenManagerSettings"),
            let settings = try? JSONDecoder().decode(TokenManagerSettings.self, from: data)
        {
            isTokenAuthEnabled = settings.isTokenAuthEnabled
            requireBiometricAuth = settings.requireBiometricAuth
        }
    }

    private func saveSettings() {
        let settings = TokenManagerSettings(
            isTokenAuthEnabled: isTokenAuthEnabled,
            requireBiometricAuth: requireBiometricAuth,
            autoRefreshTokens: true,
            tokenCleanupInterval: 3600,  // 1 hour
            maxTokenAge: 2_592_000,  // 30 days
            enableSecurityLogging: true
        )

        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "tokenManagerSettings")
        }
    }

    private func updateLastUsed(for token: StoredToken) async {
        await MainActor.run {
            if let index = activeTokens.firstIndex(where: { $0.id == token.id }) {
                let updatedToken = StoredToken(
                    id: token.id,
                    tokenType: token.tokenType,
                    provider: token.provider,
                    identifier: token.identifier,
                    encryptedAccessToken: token.encryptedAccessToken,
                    encryptedRefreshToken: token.encryptedRefreshToken,
                    scope: token.scope,
                    expiresAt: token.expiresAt,
                    refreshExpiresAt: token.refreshExpiresAt,
                    dateCreated: token.dateCreated,
                    lastUsed: Date(),
                    lastRefreshed: token.lastRefreshed
                )

                activeTokens[index] = updatedToken
                activeTokens.sort { $0.lastUsed > $1.lastUsed }
                saveTokenMetadata()
            }
        }
    }

    // MARK: - Periodic Cleanup

    private func setupTokenCleanup() {
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.cleanupExpiredTokens()
            }
        }
    }

    // MARK: - Security Logging

    private let securityMonitor: SecurityMonitor

    private func logSecurityEvent(_ event: SecurityEvent, details: [String: Any]? = nil) {
        // Map TokenManager events to SecurityMonitor authentication events
        let authEventType: SecurityMonitor.AuthEventType
        let severity: SecurityMonitor.SecurityEvent.Severity

        switch event {
        case .systemInit:
            authEventType = .authSystemInit
            severity = .info
        case .keyGeneration:
            authEventType = .authKeyGeneration
            severity = .info
        case .keyGenerationFailed:
            authEventType = .authKeyGeneration
            severity = .error
        case .tokenStored:
            authEventType = .tokenStored
            severity = .info
        case .tokenStorageFailed:
            authEventType = .tokenStored
            severity = .error
        case .tokenEncryptionFailed:
            authEventType = .tokenStored
            severity = .critical
        case .tokenRetrieved:
            authEventType = .tokenRetrieved
            severity = .info
        case .tokenNotFound:
            authEventType = .tokenRetrieved
            severity = .warning
        case .tokenDecryptionFailed:
            authEventType = .tokenRetrieved
            severity = .critical
        case .tokenDeleted:
            authEventType = .tokenDeleted
            severity = .info
        case .tokenDeletionFailed:
            authEventType = .tokenDeleted
            severity = .error
        case .tokenRefreshAttempted:
            authEventType = .tokenRefreshed
            severity = .info
        case .tokenRefreshNotAvailable:
            authEventType = .tokenRefreshed
            severity = .warning
        case .refreshTokenNotFound:
            authEventType = .tokenRefreshed
            severity = .error
        case .tokenRevocationAttempted:
            authEventType = .tokenRevoked
            severity = .info
        case .tokenRevoked:
            authEventType = .tokenRevoked
            severity = .info
        case .expiredTokensCleanup:
            authEventType = .tokenCleanup
            severity = .info
        case .authenticationFailed:
            authEventType = .biometricAuthFailed
            severity = .error
        case .biometricAuthFailed:
            authEventType = .biometricAuthFailed
            severity = .error
        }

        // Use SecurityMonitor's comprehensive authentication logging
        Task { @MainActor in
            securityMonitor.logAuthenticationEvent(
                eventType: authEventType,
                severity: severity,
                details: details ?? [:]
            )
        }
    }

    enum SecurityEvent: String {
        case systemInit = "system_init"
        case keyGeneration = "key_generation"
        case keyGenerationFailed = "key_generation_failed"
        case tokenStored = "token_stored"
        case tokenStorageFailed = "token_storage_failed"
        case tokenEncryptionFailed = "token_encryption_failed"
        case tokenRetrieved = "token_retrieved"
        case tokenNotFound = "token_not_found"
        case tokenDecryptionFailed = "token_decryption_failed"
        case tokenDeleted = "token_deleted"
        case tokenDeletionFailed = "token_deletion_failed"
        case tokenRefreshAttempted = "token_refresh_attempted"
        case tokenRefreshNotAvailable = "token_refresh_not_available"
        case refreshTokenNotFound = "refresh_token_not_found"
        case tokenRevocationAttempted = "token_revocation_attempted"
        case tokenRevoked = "token_revoked"
        case expiredTokensCleanup = "expired_tokens_cleanup"
        case authenticationFailed = "authentication_failed"
        case biometricAuthFailed = "biometric_auth_failed"
    }
}
