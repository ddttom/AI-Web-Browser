import SwiftUI

/// Privacy settings view for AI history context
/// Provides user controls for managing browsing history usage in AI responses
struct AIPrivacySettings: View {
    
    // MARK: - State
    
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var contextManager = ContextManager.shared
    @State private var showingHistoryDetails = false
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // Header
            HStack {
                Image(systemName: "shield.checkered")
                    .foregroundColor(.blue)
                Text("AI Privacy Settings")
                    .font(.headline)
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Close")
            }
            
            Divider()
            
            // History Context Toggle
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle("Enable History Context", isOn: $contextManager.isHistoryContextEnabled)
                        .toggleStyle(SwitchToggleStyle())
                    
                    Button(action: { showingHistoryDetails.toggle() }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Text("Allow AI assistant to reference your browsing history for better contextual responses")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // History Scope Selection
            if contextManager.isHistoryContextEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("History Scope")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Picker("History Scope", selection: $contextManager.historyContextScope) {
                        ForEach(HistoryContextScope.allCases, id: \.self) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    Text(scopeDescription(for: contextManager.historyContextScope))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            Divider()
            
            // Privacy Actions
            VStack(alignment: .leading, spacing: 12) {
                Text("Privacy Actions")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Button("Clear History Context Cache") {
                    contextManager.clearContextCache()
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Text("Remove any cached browsing history data used for AI context")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: 400)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
        .sheet(isPresented: $showingHistoryDetails) {
            AIHistoryDetailsView()
        }
    }
    
    // MARK: - Helper Methods
    
    private func scopeDescription(for scope: HistoryContextScope) -> String {
        switch scope {
        case .recent:
            return "Include recent browsing history (last 10 pages)"
        case .today:
            return "Include only today's browsing history"
        case .lastHour:
            return "Include only the last hour of browsing"
        case .mostVisited:
            return "Include your most frequently visited sites"
        }
    }
}

/// Detailed information about AI history context usage
struct AIHistoryDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                
                Text("AI History Context")
                    .font(.title2)
                    .fontWeight(.bold)
                
                VStack(alignment: .leading, spacing: 12) {
                    
                    PrivacyInfoSection(
                        title: "What data is used?",
                        description: "When enabled, the AI assistant can reference page titles, URLs, and visit timestamps from your browsing history to provide more contextual responses."
                    )
                    
                    PrivacyInfoSection(
                        title: "What is excluded?",
                        description: "Sensitive domains (banking, medical, authentication pages) and private browsing data are automatically excluded from AI context."
                    )
                    
                    PrivacyInfoSection(
                        title: "Data processing",
                        description: "All history analysis happens locally on your device. No browsing history is sent to external servers or AI services."
                    )
                    
                    PrivacyInfoSection(
                        title: "Privacy controls",
                        description: "You can disable history context, limit the scope, or clear cached data at any time through the privacy settings."
                    )
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Privacy Information")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 500, height: 400)
    }
}

/// Reusable privacy information section
struct PrivacyInfoSection: View {
    let title: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Secondary button style for privacy actions
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.secondary.opacity(0.3) : Color.secondary.opacity(0.1))
            )
            .foregroundColor(.primary)
            .font(.caption)
    }
}

#if DEBUG
struct AIPrivacySettings_Previews: PreviewProvider {
    static var previews: some View {
        AIPrivacySettings()
            .frame(width: 450, height: 300)
    }
}
#endif
