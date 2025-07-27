import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @EnvironmentObject private var coreDataStack: CoreDataStack
    @StateObject private var preferencesManager = PreferencesManager.shared
    
    @State private var showingCloudKitHelp = false
    @State private var showingClearDataWarning = false
    @State private var showingClearDataConfirmation = false
    @State private var isClearingData = false
    @State private var clearDataError: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // General Settings Section
            GroupBox {
                HStack {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("General")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Launch at startup", isOn: $preferencesManager.launchAtStartup)
                        }
                    }
                    Spacer()
                }
                .padding()
            }
            
            // iCloud Sync Section
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("iCloud Sync")
                            .font(.headline)
                        Spacer()
                        Button("Help") {
                            showingCloudKitHelp = true
                        }
                        .font(.caption)
                    }
                    
                    HStack {
                        Image(systemName: coreDataStack.isCloudKitReady ? "icloud" : "icloud.slash")
                            .foregroundColor(coreDataStack.isCloudKitReady ? .blue : .orange)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Status: \(cloudKitService.accountStatus.description)")
                                .font(.body)
                            
                            if coreDataStack.isCloudKitReady {
                                Text("Your prompts will sync across all your devices")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(coreDataStack.cloudKitError ?? "Sign into iCloud in System Preferences to enable sync")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if !coreDataStack.isCloudKitReady {
                            Button("Open System Preferences") {
                                openSystemPreferences()
                            }
                            .controlSize(.small)
                        } else {
                            Button("Refresh Status") {
                                cloudKitService.checkAccountStatus()
                                coreDataStack.checkCloudKitStatus()
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .padding()
            }
            
            // Data Management Section
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Data Management")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
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
                            .controlSize(.small)
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
                }
                .padding()
            }
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 500, idealWidth: 500, maxWidth: 600, minHeight: 400, idealHeight: 450, maxHeight: 550)
        .onAppear {
            preferencesManager.syncWithSystem()
        }
        .alert("iCloud Sync Help", isPresented: $showingCloudKitHelp) {
            Button("OK") { }
        } message: {
            Text("To enable iCloud sync:\n\n1. Open System Preferences\n2. Go to Apple ID\n3. Ensure iCloud Drive is enabled\n4. Sign in with your Apple ID\n\nOnce enabled, your prompts will automatically sync across all your Mac devices.")
        }
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
    
    private func openSystemPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane")!
        NSWorkspace.shared.open(url)
    }
    
    private func clearAllData() {
        isClearingData = true
        clearDataError = nil
        
        Task {
            do {
                try await performDataClear()
                
                await MainActor.run {
                    isClearingData = false
                    // Close settings window after successful clear
                    NSApplication.shared.windows.first { $0.title == "Settings" }?.close()
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
        
        // First, fetch all objects to delete them individually (this triggers proper notifications)
        let promptRequest = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
        let prompts = try context.fetch(promptRequest)
        
        let categoryRequest = NSFetchRequest<NSManagedObject>(entityName: "Category")
        let categories = try context.fetch(categoryRequest)
        
        // Delete all prompts individually to trigger proper change notifications
        for prompt in prompts {
            context.delete(prompt)
        }
        
        // Delete all categories individually to trigger proper change notifications
        for category in categories {
            context.delete(category)
        }
        
        // Save changes to trigger CloudKit sync and UI updates
        try context.save()
        
        print("Successfully cleared all account data")
        
        // Wait a moment for the deletions to process, then reload defaults
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Reload default prompts
        await reloadDefaultPrompts()
    }
    
    private func reloadDefaultPrompts() async {
        print("SettingsView: Starting to reload default prompts...")
        
        do {
            // Create and use the import service to load defaults
            let importService = DataExportImportService(viewContext: coreDataStack.viewContext)
            try await importService.loadDefaultPrompts()
            print("SettingsView: Successfully reloaded default prompts after data clear")
        } catch {
            print("SettingsView: Error reloading default prompts: \(error)")
            print("SettingsView: Error type: \(type(of: error))")
            
            // Check if the bundle contains the file
            if let url = Bundle.main.url(forResource: "DefaultPrompts", withExtension: "json") {
                print("SettingsView: DefaultPrompts.json found at: \(url.path)")
                do {
                    let data = try Data(contentsOf: url)
                    print("SettingsView: File data loaded, size: \(data.count) bytes")
                    let string = String(data: data, encoding: .utf8) ?? "Could not convert to string"
                    print("SettingsView: File contents preview: \(string.prefix(200))...")
                } catch {
                    print("SettingsView: Error reading file: \(error)")
                }
            } else {
                print("SettingsView: DefaultPrompts.json NOT found in bundle")
                print("SettingsView: Bundle path: \(Bundle.main.bundlePath)")
                print("SettingsView: Bundle resources: \(Bundle.main.paths(forResourcesOfType: "json", inDirectory: nil))")
            }
            
            // If JSON loading fails, create the exact prompt as fallback
            await createSpecificDefault()
        }
    }
    
    private func createSpecificDefault() async {
        print("SettingsView: Creating specific default prompt...")
        
        do {
            let context = coreDataStack.viewContext
            let defaultCategory = context.createCategory(name: "Agentic Programming", order: 0)
            let defaultPrompt = context.createPrompt(
                trigger: "firstprompt",
                expansion: """
You are an AI coding agent collaborating closely with me to develop and enhance applications. Your role is to support the development process by adhering strictly to these guidelines:

1. **Feature Implementation Approval:**

   * You must seek explicit approval from me before implementing any new features, modifications, or developing workarounds and fallbacks for existing functionalities.

2. **Testing Coordination:**

   * Whenever the application reaches a state requiring testing or verification, stop immediately and prompt me clearly and explicitly. Do not proceed further until I have tested the app and confirmed the results.

Now, please thoroughly review the provided codebase. After your review, summarize its overall functionality at a high level. Provide a concise but comprehensive description so we can confirm our shared understanding of the project's purpose and current state.
""",
                enabled: true,
                category: defaultCategory
            )
            try context.save()
            print("SettingsView: Created specific default prompt after data clear")
        } catch {
            print("SettingsView: Error creating specific default: \(error)")
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(CloudKitService())
            .environmentObject(CoreDataStack.shared)
    }
}