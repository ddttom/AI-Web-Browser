import SwiftUI
import UniformTypeIdentifiers

/// View for managing local AI models and model directories
struct ModelManagementView: View {
    
    @StateObject private var modelDiscovery = ModelDiscoveryService.shared
    @StateObject private var localProvider = LocalMLXProvider()
    
    @State private var showingDirectoryPicker = false
    @State private var showingModelDetails: ModelDiscoveryService.DiscoveredModel?
    @State private var isRefreshing = false
    @State private var cacheStatus: CacheStatus?
    @State private var isCleaningCache = false
    @State private var showingCacheAlert = false
    @State private var cacheAlertMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model Management")
                        .font(.headline)
                    Text("Manage local AI models and directories")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Refresh button
                Button(action: refreshModels) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing)
            }
            
            Divider()
            
            // Model Discovery Status
            modelDiscoveryStatus
            
            // Discovered Models
            discoveredModelsSection
            
            // User Model Directories
            userDirectoriesSection
            
            // Cache Management Section
            cacheManagementSection
            
            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingDirectoryPicker) {
            directoryPickerSheet
        }
        .sheet(item: $showingModelDetails) { model in
            ModelDetailsView(model: model)
        }
        .alert("Cache Management", isPresented: $showingCacheAlert) {
            Button("OK") { }
        } message: {
            Text(cacheAlertMessage)
        }
        .onAppear {
            loadCacheStatus()
        }
    }
    
    // MARK: - Model Discovery Status
    
    private var modelDiscoveryStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discovery Status")
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack {
                Circle()
                    .fill(modelDiscovery.isScanning ? .orange : .green)
                    .frame(width: 8, height: 8)
                
                Text(modelDiscovery.isScanning ? "Scanning for models..." : "Ready")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let lastScan = modelDiscovery.lastScanDate {
                    Text("Last scan: \(lastScan, style: .relative) ago")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            if modelDiscovery.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    // MARK: - Discovered Models Section
    
    private var discoveredModelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Discovered Models (\(modelDiscovery.discoveredModels.count))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button("Scan Now") {
                    refreshModels()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRefreshing)
            }
            
            if modelDiscovery.discoveredModels.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("No models found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Add model directories below or download models to standard locations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                )
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    ForEach(modelDiscovery.discoveredModels) { model in
                        ModelCard(model: model) {
                            showingModelDetails = model
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - User Directories Section
    
    private var userDirectoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Model Directories")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button("Add Directory") {
                    showingDirectoryPicker = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            let userPaths = localProvider.getUserModelDirectories()
            
            if userPaths.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("No custom directories")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Add directories where you store AI models")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(userPaths, id: \.self) { path in
                        DirectoryRow(path: path) {
                            removeDirectory(path)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Cache Management Section
    
    private var cacheManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cache Management")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button("Refresh Status") {
                    loadCacheStatus()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            if let status = cacheStatus {
                VStack(spacing: 12) {
                    // Cache status overview
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total Cache Size")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(status.formattedSize)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Cached Models")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(status.modelCount)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    
                    // Corrupted files warning
                    if !status.corruptedFiles.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Corrupted Files Detected")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("\(status.corruptedFiles.count) incomplete or corrupted files found")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button("Clean Up") {
                                cleanupCorruptedFiles()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isCleaningCache)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.orange.opacity(0.1))
                        )
                    }
                    
                    // Cache actions
                    HStack {
                        Button("Clean Corrupted Files") {
                            cleanupCorruptedFiles()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isCleaningCache)
                        
                        Button("Full Cache Reset") {
                            performFullCacheReset()
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                        .disabled(isCleaningCache)
                        
                        Spacer()
                        
                        if isCleaningCache {
                            ProgressView()
                                .controlSize(.small)
                            Text("Cleaning...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Cache directories info
                    if !status.cacheDirectories.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cache Locations")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ForEach(status.cacheDirectories, id: \.self) { directory in
                                Text(directory)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        )
                    }
                }
            } else {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading cache status...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }
        }
    }
    
    // MARK: - Directory Picker Sheet
    
    private var directoryPickerSheet: some View {
        VStack(spacing: 20) {
            Text("Add Model Directory")
                .font(.headline)
            
            Text("Select a directory containing AI models. The browser will scan this directory and its subdirectories for compatible models.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            HStack {
                Button("Cancel") {
                    showingDirectoryPicker = false
                }
                .buttonStyle(.bordered)
                
                Button("Choose Directory") {
                    chooseDirectory()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400)
    }
    
    // MARK: - Actions
    
    private func refreshModels() {
        isRefreshing = true
        
        Task {
            await localProvider.refreshModels()
            
            await MainActor.run {
                isRefreshing = false
            }
        }
    }
    
    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Directory"
        panel.message = "Select a directory containing AI models"
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await localProvider.addUserModelDirectory(url.path)
                
                await MainActor.run {
                    showingDirectoryPicker = false
                }
            }
        } else {
            showingDirectoryPicker = false
        }
    }
    
    private func removeDirectory(_ path: String) {
        Task {
            await localProvider.removeUserModelDirectory(path)
        }
    }
    
    // MARK: - Cache Management Actions
    
    private func loadCacheStatus() {
        Task {
            let status = await MLXCacheManager.shared.getCacheStatus()
            
            await MainActor.run {
                self.cacheStatus = status
            }
        }
    }
    
    private func cleanupCorruptedFiles() {
        isCleaningCache = true
        
        Task {
            do {
                try await MLXCacheManager.shared.performFullCacheCleanup()
                
                await MainActor.run {
                    self.cacheAlertMessage = "Successfully cleaned up corrupted cache files."
                    self.showingCacheAlert = true
                    self.isCleaningCache = false
                }
                
                // Refresh cache status
                loadCacheStatus()
                
            } catch {
                await MainActor.run {
                    self.cacheAlertMessage = "Failed to clean cache: \(error.localizedDescription)"
                    self.showingCacheAlert = true
                    self.isCleaningCache = false
                }
            }
        }
    }
    
    private func performFullCacheReset() {
        isCleaningCache = true
        
        Task {
            do {
                // Clear all MLX caches
                try await MLXCacheManager.shared.performFullCacheCleanup()
                
                // Also clear SimplifiedMLXRunner model
                await SimplifiedMLXRunner.shared.clearModel()
                
                await MainActor.run {
                    self.cacheAlertMessage = "Cache has been completely reset. The app will re-download models as needed."
                    self.showingCacheAlert = true
                    self.isCleaningCache = false
                    self.cacheStatus = nil
                }
                
                // Refresh cache status
                loadCacheStatus()
                
            } catch {
                await MainActor.run {
                    self.cacheAlertMessage = "Failed to reset cache: \(error.localizedDescription)"
                    self.showingCacheAlert = true
                    self.isCleaningCache = false
                }
            }
        }
    }
}

// MARK: - Model Card

struct ModelCard: View {
    let model: ModelDiscoveryService.DiscoveredModel
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Model type icon
                HStack {
                    Image(systemName: modelTypeIcon)
                        .font(.title2)
                        .foregroundColor(modelTypeColor)
                    
                    Spacer()
                    
                    Text(model.source.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Model name
                Text(model.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                // Model details
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.modelType.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(String(format: "%.1f", model.sizeGB)) GB")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Circle()
                            .fill(model.isValid ? .green : .red)
                            .frame(width: 6, height: 6)
                        
                        Text(model.isValid ? "Valid" : "Invalid")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(modelTypeColor.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private var modelTypeIcon: String {
        switch model.modelType {
        case .gemma: return "diamond.fill"
        case .llama: return "llama.fill"
        case .mistral: return "wind"
        case .phi: return "phi"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private var modelTypeColor: Color {
        switch model.modelType {
        case .gemma: return .purple
        case .llama: return .blue
        case .mistral: return .orange
        case .phi: return .green
        case .unknown: return .gray
        }
    }
}

// MARK: - Directory Row

struct DirectoryRow: View {
    let path: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "folder")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

// MARK: - Model Details View

struct ModelDetailsView: View {
    let model: ModelDiscoveryService.DiscoveredModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Model Details")
                    .font(.headline)
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            
            // Model info
            VStack(alignment: .leading, spacing: 12) {
                DetailRow(label: "Name", value: model.name)
                DetailRow(label: "Type", value: model.modelType.displayName)
                DetailRow(label: "Size", value: "\(String(format: "%.1f", model.sizeGB)) GB")
                DetailRow(label: "Source", value: model.source.displayName)
                DetailRow(label: "Path", value: model.path)
                DetailRow(label: "Valid", value: model.isValid ? "Yes" : "No")
                DetailRow(label: "Last Validated", value: model.lastValidated.formatted())
                
                if let metadata = model.metadata {
                    Divider()
                    
                    Text("Metadata")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if let contextWindow = metadata.contextWindow {
                        DetailRow(label: "Context Window", value: "\(contextWindow) tokens")
                    }
                    
                    if let quantization = metadata.quantization {
                        DetailRow(label: "Quantization", value: quantization)
                    }
                    
                    if let parameterCount = metadata.parameterCount {
                        DetailRow(label: "Parameters", value: parameterCount)
                    }
                    
                    if let architecture = metadata.architecture {
                        DetailRow(label: "Architecture", value: architecture)
                    }
                    
                    if let license = metadata.license {
                        DetailRow(label: "License", value: license)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            
            Spacer()
        }
    }
}

#Preview {
    ModelManagementView()
        .frame(width: 800, height: 600)
}
