import SwiftUI
import CoreData
import AppKit

@main
struct PromptBindApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) var openWindow

    @StateObject private var coreDataStack: CoreDataStack
    @StateObject private var cloudKitService: CloudKitService
    @StateObject private var subscriptionManager: SubscriptionManager
    @StateObject private var preferencesManager: PreferencesManager
    @StateObject private var triggerMonitorService: TriggerMonitorService
    @StateObject private var stripeService: StripeService
    @StateObject private var iCloudSyncStatusProvider: ICloudSyncStatusProvider
    
    // This service does not need to be an @StateObject as it's used via commands
    private let dataExportImportService: DataExportImportService

    init() {
        // Services that need to be created first
        let cdStack = CoreDataStack.shared
        let ckService = CloudKitService()
        let prefsManager = PreferencesManager.shared
        let subManager = SubscriptionManager.shared // Use the singleton
        
        let syncProvider = ICloudSyncStatusProvider(
            container: cdStack.persistentContainer,
            cloudKitService: ckService
        )
        
        let triggerService = TriggerMonitorService(
            viewContext: cdStack.viewContext
        )
        
        let exportService = DataExportImportService(
            viewContext: cdStack.viewContext
        )
        
        // Assign to StateObject wrappers
        _coreDataStack = StateObject(wrappedValue: cdStack)
        _cloudKitService = StateObject(wrappedValue: ckService)
        _preferencesManager = StateObject(wrappedValue: prefsManager)
        _subscriptionManager = StateObject(wrappedValue: subManager)
        _iCloudSyncStatusProvider = StateObject(wrappedValue: syncProvider)
        _triggerMonitorService = StateObject(wrappedValue: triggerService)
        _stripeService = StateObject(wrappedValue: StripeService.shared)
        
        // Assign regular property
        self.dataExportImportService = exportService
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(
                viewContext: coreDataStack.viewContext,
                triggerMonitor: triggerMonitorService,
                cloudKitService: cloudKitService
            )
            .environment(\.managedObjectContext, coreDataStack.viewContext)
            .environmentObject(coreDataStack)
            .environmentObject(cloudKitService)
            .environmentObject(subscriptionManager)
            .environmentObject(preferencesManager)
            .environmentObject(triggerMonitorService)
            .environmentObject(stripeService)
            .environmentObject(iCloudSyncStatusProvider)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 600)
        .defaultPosition(.center)
        
        MenuBarExtra("PromptBind", systemImage: "keyboard.fill") {
            VStack {
                Button("Prompts") {
                    openWindow(id: "main")
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                
                Button("Settings...") {
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",", modifiers: .command)
                
                Divider()
                
                Button("Check for Updates...") {
                    appDelegate.updater.checkForUpdates()
                }
                
                Button("Quit PromptBind...") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        
        WindowGroup(id: "settings") {
            SettingsView()
                .environmentObject(cloudKitService)
                .environmentObject(coreDataStack)
                .environmentObject(preferencesManager)
                .environmentObject(subscriptionManager)
                .environmentObject(stripeService)
                .environmentObject(iCloudSyncStatusProvider)
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 600, height: 650)
        
        .commands {
            CommandGroup(after: .importExport) {
                Button("Export Data...") {
                    dataExportImportService.exportData()
                }
                .keyboardShortcut("e", modifiers: [.command])
                
                Button("Import Data...") {
                    dataExportImportService.importData()
                }
                .keyboardShortcut("i", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let exportData = Notification.Name("exportData")
    static let importData = Notification.Name("importData")
    static let showSettings = Notification.Name("showSettings")
    static let openMainWindowAtLaunch = Notification.Name("openMainWindowAtLaunch")
}