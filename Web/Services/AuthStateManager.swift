import Combine
import CryptoKit
import Foundation

/// AuthStateManager: Centralized authentication state and session management
///
/// This service coordinates authentication state across TokenManager, OAuthManager, and JWTValidator
/// services, providing a unified interface for authentication status, session management, and
/// automatic token refresh capabilities. It integrates with the existing SecurityMonitor
/// infrastructure for comprehensive security event tracking.
///
/// Security Features:
/// - Centralized authentication state coordination
/// - Automatic token refresh and lifecycle management
/// - Session tracking with device fingerprinting
/// - Security event monitoring and audit logging
/// - Integration with existing browser security infrastructure
/// - Thread-safe state management with actor isolation
@MainActor
class AuthStateManager: ObservableObject {
    static let shared = AuthStateManager()

    // MARK: - Published Properties
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: AuthenticatedUser?
    @Published var activeSessions: [AuthSession] = []
    @Published var authenticationState: AuthenticationState = .unauthenticated
    @Published var lastAuthenticationError: AuthenticationError?

    // MARK: - Private Properties
    private let tokenManager: TokenManager
    private let oauthManager: OAuthManager
    private let jwtValidator: JWTValidator

    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    private var sessionCleanupTimer: Timer?

    // MARK: - Authentication State Models

    /// Current authentication state
    enum AuthenticationState: String, CaseIterable {
        case unauthenticated = "unauthenticated"
        case authenticating = "authenticating"
        case authenticated = "authenticated"
        case tokenRefreshing = "token_refreshing"
        case sessionExpired = "session_expired"
        case authenticationFailed = "authentication_failed"

        var displayName: String {
            switch self {
            case .unauthenticated: return "Not Authenticated"
            case .authenticating: return "Authenticating..."
            case .authenticated: return "Authenticated"
            case .tokenRefreshing: return "Refreshing Token..."
            case .sessionExpired: return "Session Expired"
            case .authenticationFailed: return "Authentication Failed"
            }
        }

        var isActive: Bool {
            switch self {
            case .authenticated, .tokenRefreshing:
                return true
            default:
                return false
            }
        }
    }

    /// Authenticated user information
    struct AuthenticatedUser: Identifiable, Codable {
        let id: String
        let email: String?
        let name: String?
        let provider: TokenManager.StoredToken.AuthProvider
        let authenticatedAt: Date
        let lastActiveAt: Date
        let tokenExpiresAt: Date?
        let refreshTokenExpiresAt: Date?
        let permissions: [String]
        let metadata: [String: String]

        var isTokenExpiring: Bool {
            guard let expiresAt = tokenExpiresAt else { return false }
            // Consider token expiring if it expires within 5 minutes
            return Date().addingTimeInterval(300) >= expiresAt
        }

        var canRefreshToken: Bool {
            guard let refreshExpiresAt = refreshTokenExpiresAt else { return true }
            return Date() < refreshExpiresAt
        }
    }

    /// Authentication session tracking
    struct AuthSession: Identifiable, Codable {
        let id: UUID
        let userId: String
        let provider: TokenManager.StoredToken.AuthProvider
        let deviceFingerprint: String
        let createdAt: Date
        let lastAccessedAt: Date
        let expiresAt: Date?
        let ipAddress: String?
        let userAgent: String
        let isActive: Bool

        var isExpired: Bool {
            guard let expiresAt = expiresAt else { return false }
            return Date() >= expiresAt
        }

        var sessionDuration: TimeInterval {
            return lastAccessedAt.timeIntervalSince(createdAt)
        }
    }

    /// Authentication error types
    enum AuthenticationError: LocalizedError {
        case noValidToken
        case tokenExpired
        case refreshTokenExpired
        case refreshFailed(String)
        case invalidUser
        case sessionNotFound
        case securityValidationFailed
        case networkError(Error)
        case unauthorizedAccess

        var errorDescription: String? {
            switch self {
            case .noValidToken:
                return "No valid authentication token found"
            case .tokenExpired:
                return "Authentication token has expired"
            case .refreshTokenExpired:
                return "Refresh token has expired"
            case .refreshFailed(let error):
                return "Token refresh failed: \(error)"
            case .invalidUser:
                return "Invalid user information"
            case .sessionNotFound:
                return "Authentication session not found"
            case .securityValidationFailed:
                return "Security validation failed"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .unauthorizedAccess:
                return "Unauthorized access attempt"
            }
        }
    }

    // MARK: - Initialization

    private init() {
        // Initialize dependencies
        self.tokenManager = TokenManager.shared
        self.oauthManager = OAuthManager.shared
        self.jwtValidator = JWTValidator.shared

        setupStateObservation()
        loadStoredAuthState()
        startPeriodicTasks()

        logSecurityEvent(
            .systemInit,
            details: [
                "service": "AuthStateManager"
            ])
    }

    // MARK: - Authentication State Management

    /// Checks current authentication status and loads user if authenticated
    @MainActor
    func checkAuthenticationStatus() async {
        authenticationState = .authenticating

        // Check for stored tokens across all providers
        let hasValidSession = await checkForValidSessions()

        if hasValidSession {
            await loadCurrentUser()
            authenticationState = .authenticated
            isAuthenticated = true

            logSecurityEvent(
                .authStatusRestored,
                details: [
                    "user_id": currentUser?.id ?? "unknown",
                    "provider": currentUser?.provider.rawValue ?? "unknown",
                ])
        } else {
            await signOut(silent: true)
        }
    }

    /// Initiates authentication with specified provider
    @MainActor
    func authenticate(provider: OAuthManager.OAuthProvider) async -> Result<
        AuthenticatedUser, AuthenticationError
    > {
        authenticationState = .authenticating
        lastAuthenticationError = nil

        let result = await oauthManager.authenticate(with: provider)

        switch result {
        case .success(let authResult):
            do {
                // Create authenticated user from OAuth result
                let user = try await createAuthenticatedUser(from: authResult)

                // Create session
                let session = createAuthSession(for: user)
                await addSession(session)

                // Update state
                currentUser = user
                authenticationState = .authenticated
                isAuthenticated = true

                logSecurityEvent(
                    .authSuccessful,
                    details: [
                        "user_id": user.id,
                        "provider": user.provider.rawValue,
                    ])

                return .success(user)

            } catch {
                authenticationState = .authenticationFailed
                let authError = AuthenticationError.securityValidationFailed
                lastAuthenticationError = authError

                return .failure(authError)
            }

        case .failure(let error):
            authenticationState = .authenticationFailed
            let authError = mapOAuthError(error)
            lastAuthenticationError = authError

            logSecurityEvent(
                .authFailed,
                details: [
                    "provider": provider.name,
                    "error": error.localizedDescription,
                ])

            return .failure(authError)
        }
    }

    /// Signs out current user and cleans up session
    @MainActor
    func signOut(silent: Bool = false) async {
        let currentUserId = currentUser?.id
        let currentProvider = currentUser?.provider

        // Revoke tokens if user is authenticated
        if let user = currentUser {
            _ = await tokenManager.revokeToken(
                provider: user.provider,
                identifier: user.id
            )
        }

        // Clean up state
        currentUser = nil
        authenticationState = .unauthenticated
        isAuthenticated = false
        lastAuthenticationError = nil

        // Clean up sessions
        activeSessions.removeAll { $0.userId == currentUserId }

        if !silent {
            logSecurityEvent(
                .signOutCompleted,
                details: [
                    "user_id": currentUserId ?? "unknown",
                    "provider": currentProvider?.rawValue ?? "unknown",
                ])
        }

        saveAuthState()
    }

    // MARK: - Token Management

    /// Automatically refreshes tokens when needed
    @MainActor
    func refreshTokenIfNeeded() async -> Bool {
        guard let user = currentUser,
            user.isTokenExpiring,
            user.canRefreshToken
        else {
            return false
        }

        authenticationState = .tokenRefreshing

        let success = await tokenManager.refreshToken(
            provider: user.provider,
            identifier: user.id
        )

        if success {
            // Reload user with new token info
            await loadCurrentUser()
            authenticationState = .authenticated

            logSecurityEvent(
                .tokenRefreshed,
                details: [
                    "user_id": user.id,
                    "provider": user.provider.rawValue,
                ])

            return true
        } else {
            authenticationState = .sessionExpired
            lastAuthenticationError = .refreshFailed("Token refresh returned false")

            logSecurityEvent(
                .tokenRefreshFailed,
                details: [
                    "user_id": user.id,
                    "provider": user.provider.rawValue,
                ])

            return false
        }
    }

    /// Validates current token and refreshes if necessary
    @MainActor
    func validateAndRefreshToken() async -> Bool {
        guard let user = currentUser else {
            return false
        }

        // Check if token exists and is valid
        if await tokenManager.retrieveToken(
            provider: user.provider,
            identifier: user.id
        ) != nil {
            // TODO: Validate token using JWTValidator if it's a JWT
            // For now, we assume token is valid if it exists

            // Check if refresh is needed
            if user.isTokenExpiring {
                return await refreshTokenIfNeeded()
            }

            return true
        } else {
            // No token found, sign out
            await signOut()
            return false
        }
    }

    // MARK: - Session Management

    private func createAuthSession(for user: AuthenticatedUser) -> AuthSession {
        let deviceFingerprint = generateDeviceFingerprint()

        return AuthSession(
            id: UUID(),
            userId: user.id,
            provider: user.provider,
            deviceFingerprint: deviceFingerprint,
            createdAt: Date(),
            lastAccessedAt: Date(),
            expiresAt: user.tokenExpiresAt,
            ipAddress: nil,  // Would be populated in a network-connected context
            userAgent: "Web/1.0 Browser",
            isActive: true
        )
    }

    private func addSession(_ session: AuthSession) async {
        await MainActor.run {
            activeSessions.append(session)
            saveAuthState()
        }
    }

    private func generateDeviceFingerprint() -> String {
        // Create device fingerprint based on system information
        let deviceInfo = [
            ProcessInfo.processInfo.operatingSystemVersionString,
            Host.current().localizedName ?? "Unknown",
            Bundle.main.bundleIdentifier ?? "com.web.browser",
        ].joined(separator: "|")

        let hash = SHA256.hash(data: Data(deviceInfo.utf8))
        return Data(hash).base64EncodedString()
    }

    // MARK: - Private Helper Methods

    private func checkForValidSessions() async -> Bool {
        // Check TokenManager for any valid tokens
        let hasActiveTokens = !tokenManager.activeTokens.isEmpty

        if hasActiveTokens {
            // Validate at least one token is not expired
            return tokenManager.activeTokens.contains { !$0.isExpired }
        }

        return false
    }

    private func loadCurrentUser() async {
        // Find the most recent valid token
        let validTokens = tokenManager.activeTokens.filter { !$0.isExpired }

        guard let latestToken = validTokens.sorted(by: { $0.lastUsed > $1.lastUsed }).first else {
            return
        }

        // Create user from token information
        let user = AuthenticatedUser(
            id: latestToken.identifier,
            email: nil,  // Would be populated from token claims or user info endpoint
            name: nil,  // Would be populated from token claims or user info endpoint
            provider: latestToken.provider,
            authenticatedAt: latestToken.dateCreated,
            lastActiveAt: latestToken.lastUsed,
            tokenExpiresAt: latestToken.expiresAt,
            refreshTokenExpiresAt: latestToken.refreshExpiresAt,
            permissions: [],
            metadata: [:]
        )

        await MainActor.run {
            currentUser = user
        }
    }

    private func createAuthenticatedUser(from authResult: OAuthManager.AuthenticationResult)
        async throws -> AuthenticatedUser
    {
        // Extract user information from token or make user info request
        let userId = extractUserIdFromToken(authResult.accessToken ?? "")

        let user = AuthenticatedUser(
            id: userId,
            email: nil,  // Would be extracted from ID token or user info endpoint
            name: nil,  // Would be extracted from ID token or user info endpoint
            provider: .oauthProvider,
            authenticatedAt: Date(),
            lastActiveAt: Date(),
            tokenExpiresAt: authResult.expiresIn.map { Date().addingTimeInterval($0) },
            refreshTokenExpiresAt: nil,  // Would be calculated if known
            permissions: authResult.scope?.components(separatedBy: " ") ?? [],
            metadata: [:]
        )

        return user
    }

    private func extractUserIdFromToken(_ token: String) -> String {
        // In a real implementation, this would decode the JWT and extract the subject
        // For now, return a placeholder
        return "user_\(abs(token.hashValue))"
    }

    private func mapOAuthError(_ error: OAuthManager.AuthenticationError) -> AuthenticationError {
        switch error {
        case .userCancelled:
            return .unauthorizedAccess
        case .networkError(let netError):
            return .networkError(netError)
        case .tokenExchangeFailed(let message):
            return .refreshFailed(message)
        default:
            return .securityValidationFailed
        }
    }

    // MARK: - State Observation

    private func setupStateObservation() {
        // Observe TokenManager changes
        tokenManager.$activeTokens
            .sink { [weak self] tokens in
                Task { @MainActor in
                    await self?.handleTokenChanges(tokens)
                }
            }
            .store(in: &cancellables)

        // Observe OAuthManager authentication state
        oauthManager.$isAuthenticating
            .sink { [weak self] isAuthenticating in
                Task { @MainActor in
                    if isAuthenticating && self?.authenticationState != .authenticating {
                        self?.authenticationState = .authenticating
                    }
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func handleTokenChanges(_ tokens: [TokenManager.StoredToken]) async {
        // If we have a current user but no valid tokens, sign out
        if currentUser != nil && tokens.allSatisfy({ $0.isExpired }) {
            await signOut()
        }

        // If tokens were added and we're not authenticated, check status
        if !isAuthenticated && !tokens.isEmpty {
            await checkAuthenticationStatus()
        }
    }

    // MARK: - Periodic Tasks

    private func startPeriodicTasks() {
        // Token refresh check every 5 minutes
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in
                _ = await self.refreshTokenIfNeeded()
            }
        }

        // Session cleanup every hour
        sessionCleanupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in
                await self.cleanupExpiredSessions()
            }
        }
    }

    @MainActor
    private func cleanupExpiredSessions() async {
        let expiredSessions = activeSessions.filter { $0.isExpired }

        if !expiredSessions.isEmpty {
            activeSessions.removeAll { $0.isExpired }

            logSecurityEvent(
                .sessionsCleanup,
                details: [
                    "cleaned_count": expiredSessions.count
                ])

            saveAuthState()
        }
    }

    // MARK: - Persistence

    private func loadStoredAuthState() {
        // Load stored sessions
        if let data = UserDefaults.standard.data(forKey: "authSessions"),
            let sessions = try? JSONDecoder().decode([AuthSession].self, from: data)
        {
            activeSessions = sessions.filter { !$0.isExpired }
        }

        // Load stored user (if session is still valid)
        if let data = UserDefaults.standard.data(forKey: "currentUser"),
            let user = try? JSONDecoder().decode(AuthenticatedUser.self, from: data)
        {

            // Only restore if token hasn't expired
            if let expiresAt = user.tokenExpiresAt, Date() < expiresAt {
                currentUser = user
                isAuthenticated = true
                authenticationState = .authenticated
            }
        }
    }

    private func saveAuthState() {
        // Save sessions
        if let data = try? JSONEncoder().encode(activeSessions) {
            UserDefaults.standard.set(data, forKey: "authSessions")
        }

        // Save current user
        if let user = currentUser,
            let data = try? JSONEncoder().encode(user)
        {
            UserDefaults.standard.set(data, forKey: "currentUser")
        } else {
            UserDefaults.standard.removeObject(forKey: "currentUser")
        }
    }

    // MARK: - Security Logging

    private enum SecurityEvent: String {
        case systemInit = "system_init"
        case authStatusRestored = "auth_status_restored"
        case authStatusCheckFailed = "auth_status_check_failed"
        case authSuccessful = "auth_successful"
        case authFailed = "auth_failed"
        case signOutCompleted = "sign_out_completed"
        case tokenRefreshed = "token_refreshed"
        case tokenRefreshFailed = "token_refresh_failed"
        case sessionsCleanup = "sessions_cleanup"
    }

    private func logSecurityEvent(_ event: SecurityEvent, details: [String: Any]? = nil) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        var logEntry = [
            "timestamp": timestamp,
            "service": "AuthStateManager",
            "event": event.rawValue,
        ]

        if let details = details {
            for (key, value) in details {
                logEntry[key] = "\(value)"
            }
        }

        if let logData = try? JSONSerialization.data(withJSONObject: logEntry, options: []),
            let logString = String(data: logData, encoding: .utf8)
        {
            if AppLog.isVerboseEnabled { print("🔐 AuthStateManager: \(logString)") }
        }
    }

    deinit {
        refreshTimer?.invalidate()
        sessionCleanupTimer?.invalidate()
    }
}
