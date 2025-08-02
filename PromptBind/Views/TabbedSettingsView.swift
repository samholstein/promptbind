import SwiftUI
import Sparkle

struct TabbedSettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @EnvironmentObject private var coreDataStack: CoreDataStack
    @EnvironmentObject private var preferencesManager: PreferencesManager
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .environmentObject(preferencesManager)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            UpdatesSettingsView()
                .tabItem {
                    Label("Updates", systemImage: "arrow.down.circle")
                }
            
            CloudSettingsView()
                .environmentObject(cloudKitService)
                .environmentObject(coreDataStack)
                .tabItem {
                    Label("iCloud", systemImage: "icloud")
                }
            
            DataSettingsView()
                .environmentObject(coreDataStack)
                .environmentObject(preferencesManager)
                .tabItem {
                    Label("Data", systemImage: "externaldrive")
                }
        }
        .frame(width: 500, height: 400)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject private var preferencesManager: PreferencesManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General")
                .font(.title2)
                .fontWeight(.bold)
            
            Toggle("Launch at startup", isOn: $preferencesManager.launchAtStartup)
            
            Spacer()
        }
        .padding()
        .onAppear {
            preferencesManager.syncWithSystem()
        }
    }
}

struct UpdatesSettingsView: View {
    private var updaterController: SPUStandardUpdaterController? {
        (NSApplication.shared.delegate as? AppDelegate)?.updaterController
    }
    
    private var autoCheckBinding: Binding<Bool> {
        Binding(
            get: { self.updaterController?.updater.automaticallyChecksForUpdates ?? true },
            set: { newValue in self.updaterController?.updater.automaticallyChecksForUpdates = newValue }
        )
    }

    private var autoDownloadBinding: Binding<Bool> {
        Binding(
            get: { self.updaterController?.updater.automaticallyDownloadsUpdates ?? false },
            set: { newValue in self.updaterController?.updater.automaticallyDownloadsUpdates = newValue }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Updates")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Automatically check for updates", isOn: autoCheckBinding)
                    .disabled(updaterController == nil)
                
                Toggle("Automatically download updates", isOn: autoDownloadBinding)
                    .disabled(updaterController == nil)
                
                HStack {
                    Spacer()
                    Button("Check for Updates Now") {
                        updaterController?.checkForUpdates(nil)
                    }
                    .disabled(updaterController == nil)
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

struct CloudSettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @EnvironmentObject private var coreDataStack: CoreDataStack
    @EnvironmentObject private var iCloudSyncStatusProvider: ICloudSyncStatusProvider
    @State private var showingCloudKitHelp = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("iCloud Sync")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Help") {
                    showingCloudKitHelp = true
                }
                .font(.caption)
            }
            
            NewiCloudSyncStatusView()
                .environmentObject(iCloudSyncStatusProvider)
            
            Spacer()
        }
        .padding()
        .alert("iCloud Sync Help", isPresented: $showingCloudKitHelp) {
            Button("OK") { }
        } message: {
            Text("To enable iCloud sync:\n\n1. Open System Preferences\n2. Go to Apple ID\n3. Ensure iCloud Drive is enabled\n4. Sign in with your Apple ID\n\nOnce enabled, your prompts will automatically sync across all your Mac devices.")
        }
    }
}

struct DataSettingsView: View {
    @EnvironmentObject private var coreDataStack: CoreDataStack
    @EnvironmentObject private var preferencesManager: PreferencesManager
    
    @State private var showingClearDataWarning = false
    @State private var showingClearDataConfirmation = false
    @State private var isClearingData = false
    @State private var clearDataError: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Data Management")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clear Account Data")
                            .font(.body)
                        Text("Remove all prompts and categories from this device and iCloud")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Clear Data...") {
                        showingClearDataWarning = true
                    }
                    .foregroundColor(.red)
                    .disabled(isClearingData)
                }
                
                if isClearingData {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Clearing data...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let error = clearDataError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .alert("Clear Account Data", isPresented: $showingClearDataWarning) {
            Button("Cancel", role: .cancel) { }
            Button("Continue", role: .destructive) {
                showingClearDataConfirmation = true
            }
        } message: {
            Text("⚠️ This will permanently delete ALL your prompts and categories from this device and iCloud.\n\nThis action cannot be undone and will affect all devices signed into your iCloud account.\n\nAre you sure you want to continue?")
        }
        .alert("Final Confirmation", isPresented: $showingClearDataConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Everything", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("This is your final warning.\n\nType 'DELETE' to confirm you want to permanently erase all your PromptBind data from this device and iCloud.")
        }
    }
    
    private func clearAllData() {
        isClearingData = true
        clearDataError = nil
        
        Task {
            do {
                try await performDataClear()
                
                await MainActor.run {
                    preferencesManager.hasCompletedOnboarding = false
                    NSApplication.shared.terminate(nil)
                }
            } catch {
                await MainActor.run {
                    isClearingData = false
                    clearDataError = "Failed to clear data: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func performDataClear() async throws {
        let context = coreDataStack.viewContext
        
        let promptRequest = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
        let prompts = try context.fetch(promptRequest)
        
        let categoryRequest = NSFetchRequest<NSManagedObject>(entityName: "Category")
        let categories = try context.fetch(categoryRequest)
        
        for prompt in prompts {
            context.delete(prompt)
        }
        
        for category in categories {
            context.delete(category)
        }
        
        try context.save()
        print("Successfully cleared all account data")
    }
}