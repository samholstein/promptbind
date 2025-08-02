import SwiftUI
import Sparkle

struct SettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @EnvironmentObject private var coreDataStack: CoreDataStack
    @EnvironmentObject private var preferencesManager: PreferencesManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var stripeService: StripeService
    @EnvironmentObject private var iCloudSyncStatusProvider: ICloudSyncStatusProvider
    
    @State private var showingCloudKitHelp = false
    @State private var showingClearDataWarning = false
    @State private var showingClearDataConfirmation = false
    @State private var isClearingData = false
    @State private var clearDataError: String?
    @State private var showingUpgradePrompt = false
    
    // Safer Sparkle updater access
    private var updater: SPUUpdater? {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            return nil
        }
        return appDelegate.updater
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Subscription Section (new - at the top)
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Subscription")
                            .font(.headline)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Status:")
                                        .font(.body)
                                    Text(subscriptionManager.subscriptionStatus.displayName)
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(subscriptionStatusColor)
                                    
                                    // Add sync status indicator
                                    if let lastSyncDate = subscriptionManager.lastSyncDate {
                                        Text("(synced \(lastSyncDate.formatted(.relative(presentation: .named))))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                HStack {
                                    Text("Prompts:")
                                        .font(.body)
                                    if subscriptionManager.subscriptionStatus.isActive {
                                        Text("Unlimited")
                                            .font(.body)
                                            .foregroundColor(.green)
                                    } else {
                                        Text("\(subscriptionManager.promptCount)/5")
                                            .font(.body)
                                            .foregroundColor(subscriptionManager.promptCount >= 5 ? .red : .primary)
                                    }
                                }
                                
                                // Add error display
                                if let error = subscriptionManager.lastError {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                        Text(error)
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                            .lineLimit(2)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            if !subscriptionManager.subscriptionStatus.isActive {
                                Button("Upgrade to Pro") {
                                    showingUpgradePrompt = true
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                // Add refresh button for Pro users
                                Button {
                                    Task {
                                        await subscriptionManager.refreshSubscriptionStatus()
                                    }
                                } label: {
                                    if subscriptionManager.isCheckingStripeStatus {
                                        HStack(spacing: 4) {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                            Text("Refreshing...")
                                        }
                                    } else {
                                        Text("Refresh Status")
                                    }
                                }
                                .controlSize(.small)
                                .disabled(subscriptionManager.isCheckingStripeStatus)
                            }
                        }
                    }
                    .padding()
                }
                
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
                
                // Updates Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Updates")
                            .font(.headline)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Automatically check for updates")
                                    .font(.body)
                                Text("PromptBind will check for updates in the background")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { updater?.automaticallyChecksForUpdates ?? true },
                                set: { updater?.automaticallyChecksForUpdates = $0 }
                            ))
                            .toggleStyle(.switch)
                            .disabled(updater == nil)
                        }
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Automatically download updates")
                                    .font(.body)
                                Text("Updates will download and install automatically")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { updater?.automaticallyDownloadsUpdates ?? false },
                                set: { updater?.automaticallyDownloadsUpdates = $0 }
                            ))
                            .toggleStyle(.switch)
                            .disabled(updater == nil)
                        }
                        
                        HStack {
                            Spacer()
                            Button("Check for Updates Now") {
                                updater?.checkForUpdates()
                            }
                            .controlSize(.small)
                            .disabled(updater == nil)
                        }
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
                        
                        // New detailed status view
                        NewiCloudSyncStatusView()
                            .environmentObject(iCloudSyncStatusProvider)
                    }
                    .padding()
                }
                
                // Data Management Section (commented for production)
                /*
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
                */
                
                Spacer(minLength: 32)
            }
            .padding()
            .frame(minWidth: 500, idealWidth: 500, maxWidth: 600, minHeight: 500, idealHeight: 650, maxHeight: .infinity)
        }
        .onAppear {
            preferencesManager.syncWithSystem()
        }
        .sheet(isPresented: $showingUpgradePrompt) {
            UpgradePromptView()
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
    
    // MARK: - Computed Properties
    
    private var subscriptionStatusColor: Color {
        switch subscriptionManager.subscriptionStatus {
        case .free:
            return .secondary
        case .subscribed:
            return .green
        case .expired:
            return .red
        }
    }
    
    // MARK: - Actions
    
    private func clearAllData() {
        isClearingData = true
        clearDataError = nil
        
        Task {
            do {
                try await performDataClear()
                
                await MainActor.run {
                    // Reset the onboarding flag to ensure the welcome sequence shows on next launch.
                    preferencesManager.hasCompletedOnboarding = false
                    
                    // Quit the app to complete the reset process.
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
    }
}

// MARK: - iCloud Sync Status Subview
struct NewiCloudSyncStatusView: View {
    @EnvironmentObject var syncProvider: ICloudSyncStatusProvider
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // Status Icon
                Group {
                    switch syncProvider.detailedSyncStatus {
                    case .syncing:
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    case .successfullySynced:
                        Image(systemName: "icloud.fill")
                            .foregroundColor(.blue)
                    case .error:
                        Image(systemName: "icloud.slash.fill")
                            .foregroundColor(.red)
                    case .noAccount, .icloudRestricted, .notPermitted:
                        Image(systemName: "icloud.slash")
                            .foregroundColor(.orange)
                    case .networkUnavailable:
                        Image(systemName: "wifi.slash")
                            .foregroundColor(.orange)
                    default:
                        Image(systemName: "icloud")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.title3)

                // Status Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(syncProvider.detailedSyncStatus.userDescription)
                        .font(.body)
                        .lineLimit(2)

                    if case .successfullySynced(let date) = syncProvider.detailedSyncStatus, let syncDate = date {
                         Text("Last sync: \(syncDate.formatted(date: .abbreviated, time: .shortened))")
                             .font(.caption)
                             .foregroundColor(.secondary)
                    } else if syncProvider.detailedSyncStatus == .idle {
                         Text("Changes will sync automatically")
                             .font(.caption)
                             .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button("Sync Now") {
                    syncProvider.triggerCloudKitSync()
                }
                .controlSize(.small)
                .disabled(!syncProvider.detailedSyncStatus.canSyncNow)
            }
            
            if case .error(let message) = syncProvider.detailedSyncStatus {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(CloudKitService())
            .environmentObject(CoreDataStack.shared)
            .environmentObject(PreferencesManager.shared)
            .environmentObject(SubscriptionManager.shared)
            .environmentObject(StripeService.shared)
            .environmentObject(ICloudSyncStatusProvider(container: CoreDataStack.shared.persistentContainer, cloudKitService: CloudKitService()))
    }
}