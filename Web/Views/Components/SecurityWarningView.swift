import SwiftUI
import WebKit

/// SecurityWarningView
///
/// A comprehensive security warning interface for TLS certificate validation issues.
/// Designed to educate users about security risks while providing clear options.
///
/// Design Principles:
/// - Clear explanation of security risks
/// - No "just click OK" pattern that trains users to ignore warnings
/// - Progressive disclosure of technical details
/// - Emphasis on going back rather than proceeding with risk
struct SecurityWarningView: View {
    let challenge: URLAuthenticationChallenge
    let error: CertificateManager.CertificateError
    let host: String
    let port: Int

    @State private var showTechnicalDetails = false
    @State private var userUnderstandsRisk = false
    @State private var isShowingAdvancedOptions = false
    @Environment(\.dismiss) private var dismiss

    // Completion handlers
    let onProceedWithRisk: () -> Void
    let onGoBack: () -> Void
    let onAlwaysAllow: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header with security icon and primary message
            headerSection

            // Main warning content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    warningDetailsSection
                    technicalDetailsSection
                    risksExplanationSection

                    if isShowingAdvancedOptions {
                        advancedOptionsSection
                    }
                }
                .padding(24)
            }

            // Action buttons
            actionButtonsSection
        }
        .frame(width: 500, height: isShowingAdvancedOptions ? 650 : 550)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(error.securitySeverity.color.opacity(0.3), lineWidth: 2)
        )
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.3), radius: 20)
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Security warning icon
            Image(systemName: securityIconName)
                .font(.system(size: 48, weight: .regular))
                .foregroundColor(error.securitySeverity.color)

            // Primary message
            VStack(spacing: 8) {
                Text("Security Warning")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.primary)

                Text("This website's security certificate has issues")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Host information
            VStack(spacing: 4) {
                Text(host)
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)

                if port != 443 {
                    Text("Port: \(port)")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .padding(.top, 32)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [
                    error.securitySeverity.color.opacity(0.1),
                    Color.clear,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var warningDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("What's Wrong?", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundColor(error.securitySeverity.color)

            Text(error.localizedDescription)
                .font(.body)
                .foregroundColor(.primary)

            // Severity-specific explanation
            Text(severityExplanation)
                .font(.callout)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    private var technicalDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { showTechnicalDetails.toggle() }) {
                HStack {
                    Label("Technical Details", systemImage: "info.circle")
                        .font(.headline)

                    Spacer()

                    Image(systemName: showTechnicalDetails ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            if showTechnicalDetails {
                VStack(alignment: .leading, spacing: 8) {
                    technicalDetailRow("Host", host)
                    technicalDetailRow("Port", "\(port)")
                    technicalDetailRow("Error Type", error.localizedDescription)
                    technicalDetailRow(
                        "Security Level", CertificateManager.shared.securityLevel.rawValue)

                    if let serverTrust = challenge.protectionSpace.serverTrust {
                        let certCount = SecTrustGetCertificateCount(serverTrust)
                        technicalDetailRow("Certificates", "\(certCount) in chain")

                        if let certificateChain = SecTrustCopyCertificateChain(serverTrust),
                            CFArrayGetCount(certificateChain) > 0,
                            let certificate = CFArrayGetValueAtIndex(certificateChain, 0)
                        {
                            let secCertificate = certificate as! SecCertificate
                            let summary = certificateSummary(secCertificate)
                            technicalDetailRow("Subject", summary.subject)
                            technicalDetailRow("Issuer", summary.issuer)
                            technicalDetailRow("Valid Until", summary.notAfter)
                        }
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(12)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }

    private var risksExplanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Security Risks", systemImage: "shield.slash.fill")
                .font(.headline)
                .foregroundColor(.red)

            VStack(alignment: .leading, spacing: 8) {
                riskItem("Attackers could intercept your data", "person.crop.rectangle.badge.xmark")
                riskItem("Your passwords and personal information could be stolen", "key.slash")
                riskItem("Malicious content could be injected into pages", "doc.text.badge.plus")
                riskItem("Your browsing activity could be monitored", "eye.slash")
            }
        }
        .padding(16)
        .background(Color.red.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
    }

    private var advancedOptionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Advanced Options", systemImage: "gearshape.fill")
                .font(.headline)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("I understand the security risks", isOn: $userUnderstandsRisk)
                    .toggleStyle(.checkbox)

                if userUnderstandsRisk {
                    Text(
                        "⚠️ Only proceed if you absolutely trust this website and understand the risks."
                    )
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.leading, 24)
                }
            }

            Divider()

            // Exception options (only for appropriate error types)
            if canAllowException {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exception Options")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(
                        "You can create an exception for this specific website. This will remember your choice but may still pose security risks."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }

    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            Divider()

            HStack(spacing: 12) {
                // Primary action: Go back (safe option)
                Button(action: onGoBack) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text("Go Back (Recommended)")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .keyboardShortcut(.escape)
                .keyboardShortcut(.return)

                // Advanced button
                Button(action: { isShowingAdvancedOptions.toggle() }) {
                    Text(isShowingAdvancedOptions ? "Hide Advanced" : "Advanced...")
                        .font(.system(size: 16))
                        .frame(minWidth: 120)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderless)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            // Risky actions (only shown in advanced mode)
            if isShowingAdvancedOptions {
                HStack(spacing: 12) {
                    // Temporary proceed
                    Button(action: onProceedWithRisk) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                            Text("Proceed This Time")
                        }
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange)
                        .cornerRadius(8)
                    }
                    .disabled(!userUnderstandsRisk)

                    // Always allow (only for appropriate cases)
                    if canAllowException {
                        Button(action: onAlwaysAllow) {
                            HStack {
                                Image(systemName: "checkmark.shield")
                                Text("Always Allow")
                            }
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.red)
                            .cornerRadius(8)
                        }
                        .disabled(!userUnderstandsRisk)
                    }
                }
            }
        }
        .padding(16)
    }

    // MARK: - Helper Views

    private func technicalDetailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text("\(label):")
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .foregroundColor(.primary)
            Spacer()
        }
    }

    private func riskItem(_ text: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.red)
                .frame(width: 16)
            Text(text)
                .font(.callout)
                .foregroundColor(.primary)
        }
    }

    // MARK: - Computed Properties

    private var securityIconName: String {
        switch error.securitySeverity {
        case .low:
            return "exclamationmark.triangle"
        case .medium:
            return "exclamationmark.triangle.fill"
        case .high:
            return "shield.slash"
        case .critical:
            return "shield.slash.fill"
        }
    }

    private var severityExplanation: String {
        switch error.securitySeverity {
        case .low:
            return "This is a minor security concern that may not pose immediate risk."
        case .medium:
            return "This represents a moderate security risk that should be addressed."
        case .high:
            return "This is a serious security issue that puts your data at risk."
        case .critical:
            return "This is a critical security vulnerability that should not be ignored."
        }
    }

    private var canAllowException: Bool {
        // Only allow exceptions for certain error types and security levels
        switch error {
        case .expired, .selfSigned, .hostnameMismatch:
            return CertificateManager.shared.securityLevel != .paranoid
        case .untrustedRoot, .revoked, .pinningFailure:
            return false  // Never allow exceptions for critical security issues
        case .weakSignature, .invalidChain:
            return CertificateManager.shared.securityLevel == .relaxed
        case .unknown:
            return CertificateManager.shared.securityLevel == .relaxed
        }
    }

    private func certificateSummary(_ certificate: SecCertificate) -> (
        subject: String, issuer: String, notAfter: String
    ) {
        // Extract certificate information
        var subject = "Unknown"
        var issuer = "Unknown"
        var notAfter = "Unknown"

        if let values = SecCertificateCopyValues(certificate, nil, nil) as? [String: Any] {
            // Extract subject
            if let subjectDict = values[kSecOIDX509V1SubjectName as String] as? [String: Any],
                let subjectValue = subjectDict[kSecPropertyKeyValue as String] as? [[String: Any]]
            {
                subject = extractCommonName(from: subjectValue) ?? "Unknown"
            }

            // Extract issuer
            if let issuerDict = values[kSecOIDX509V1IssuerName as String] as? [String: Any],
                let issuerValue = issuerDict[kSecPropertyKeyValue as String] as? [[String: Any]]
            {
                issuer = extractCommonName(from: issuerValue) ?? "Unknown"
            }

            // Extract expiration date
            if let notAfterDict = values[kSecOIDX509V1ValidityNotAfter as String] as? [String: Any],
                let notAfterValue = notAfterDict[kSecPropertyKeyValue as String] as? Date
            {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                notAfter = formatter.string(from: notAfterValue)
            }
        }

        return (subject: subject, issuer: issuer, notAfter: notAfter)
    }

    private func extractCommonName(from nameArray: [[String: Any]]) -> String? {
        for component in nameArray {
            if let label = component[kSecPropertyKeyLabel as String] as? String,
                label == "Common Name" || label == "CN",
                let value = component[kSecPropertyKeyValue as String] as? String
            {
                return value
            }
        }
        return nil
    }
}

// MARK: - Container View for Sheet Presentation

struct SecurityWarningSheet: View {
    @State private var isPresented = false
    @State private var currentChallenge: URLAuthenticationChallenge?
    @State private var currentError: CertificateManager.CertificateError?
    @State private var currentHost: String?
    @State private var currentPort: Int?

    var body: some View {
        Color.clear
            .sheet(isPresented: $isPresented) {
                if let challenge = currentChallenge,
                    let error = currentError,
                    let host = currentHost,
                    let port = currentPort
                {
                    SecurityWarningView(
                        challenge: challenge,
                        error: error,
                        host: host,
                        port: port,
                        onProceedWithRisk: {
                            // Handle proceed with risk
                            NotificationCenter.default.post(
                                name: .userGrantedTemporaryCertificateException,
                                object: nil,
                                userInfo: ["challenge": challenge]
                            )
                            isPresented = false
                        },
                        onGoBack: {
                            // Handle go back (safe option)
                            isPresented = false
                        },
                        onAlwaysAllow: {
                            // Handle always allow
                            CertificateManager.shared.grantException(for: host, port: port)
                            NotificationCenter.default.post(
                                name: .userGrantedCertificateException,
                                object: nil,
                                userInfo: ["challenge": challenge, "host": host, "port": port]
                            )
                            isPresented = false
                        }
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showCertificateSecurityWarning)) {
                notification in
                if let challenge = notification.userInfo?["challenge"]
                    as? URLAuthenticationChallenge,
                    let error = notification.userInfo?["error"]
                        as? CertificateManager.CertificateError,
                    let host = notification.userInfo?["host"] as? String,
                    let port = notification.userInfo?["port"] as? Int
                {

                    currentChallenge = challenge
                    currentError = error
                    currentHost = host
                    currentPort = port
                    isPresented = true
                }
            }
    }
}

// MARK: - Additional Notification Names

extension Notification.Name {
    static let userGrantedTemporaryCertificateException = Notification.Name(
        "userGrantedTemporaryCertificateException")
}

// MARK: - Preview

#Preview {
    // Create a mock challenge for preview
    let mockChallenge = URLAuthenticationChallenge(
        protectionSpace: URLProtectionSpace(
            host: "example.com",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        ),
        proposedCredential: nil,
        previousFailureCount: 0,
        failureResponse: nil,
        error: nil,
        sender: MockChallengeSender()
    )

    SecurityWarningView(
        challenge: mockChallenge,
        error: .expired,
        host: "example.com",
        port: 443,
        onProceedWithRisk: {},
        onGoBack: {},
        onAlwaysAllow: {}
    )
    .padding()
}

// Mock class for preview
private class MockChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}
