import SwiftUI
import CoreData
import AppKit

@main
struct PromptBindApp: App {
    // AppDelegate for managing app lifecycle events, like activation policy.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @StateObject private var coreDataStack = CoreDataStack.shared
    @StateObject private var cloudKitService = CloudKitService()
    @StateObject private var preferencesManager = PreferencesManager.shared
    
    // Environment value to open new windows.
    @Environment(\.openWindow) var openWindow

    @State private var showingAccessibilityPermissionSheet = false
    @State private var permissionCheckTimer: Timer?
    
    // Keep trigger monitor at app level to ensure it persists.
    @State private var triggerMonitor: TriggerMonitorService?

    var body: some Scene {
        // Make the main window the primary scene - this should open automatically at launch
        WindowGroup(id: "main") {
            ContentView(
                viewContext: coreDataStack.viewContext,
                triggerMonitor: triggerMonitor,
                cloudKitService: cloudKitService
            )
            .environment(\.managedObjectContext, coreDataStack.viewContext)
            .environmentObject(coreDataStack)
            .environmentObject(cloudKitService)
            .environmentObject(preferencesManager)
            .sheet(isPresented: $showingAccessibilityPermissionSheet) {
                AccessibilityPermissionView()
            }
            .onAppear(perform: setupApp) // Setup when window appears
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 600)
        .defaultPosition(.center)
        
        // MenuBarExtra is now secondary - provides menu access
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
                
                Button("Quit PromptBind") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        
        // Dedicated Settings Window. Not opened at launch.
        WindowGroup(id: "settings") {
            SettingsView()
                .environmentObject(cloudKitService)
                .environmentObject(coreDataStack)
                .environmentObject(preferencesManager)
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 500, height: 400)
        .commands {
            // These commands are available when one of the windows is focused.
            CommandGroup(after: .importExport) {
                Button("Export Data...") {
                    NotificationCenter.default.post(name: .exportData, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command])
                
                Button("Import Data...") {
                    NotificationCenter.default.post(name: .importData, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])
            }
        }
    }
    
    // Moved setup logic into a single function.
    private func setupApp() {
        print("PromptBindApp: setupApp called")
        
        // Initialize trigger monitor if not already created.
        // This ensures it's created only once.
        if triggerMonitor == nil {
            triggerMonitor = TriggerMonitorService(viewContext: coreDataStack.viewContext)
            print("PromptBindApp: Created TriggerMonitorService")
        }
        
        // Check accessibility permission and start monitoring if needed.
        checkAccessibilityPermission()
        if !AXIsProcessTrusted() {
            // Start polling for permission status.
            permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                checkAccessibilityPermission()
            }
        } else {
            // Permission is already granted, start monitoring.
            triggerMonitor?.startMonitoring()
        }
    }

    private func checkAccessibilityPermission() {
        let isTrusted = AXIsProcessTrusted()
        print("PromptBindApp: Accessibility permission check - isTrusted: \(isTrusted)")
        
        if !isTrusted && !showingAccessibilityPermissionSheet {
            print("PromptBindApp: Showing accessibility permission sheet")
            showingAccessibilityPermissionSheet = true
        } else if isTrusted && showingAccessibilityPermissionSheet {
            print("PromptBindApp: Permission granted, hiding sheet")
            showingAccessibilityPermissionSheet = false
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
            triggerMonitor?.startMonitoring()
        }
    }
}

extension Notification.Name {
    static let exportData = Notification.Name("exportData")
    static let importData = Notification.Name("importData")
    static let showSettings = Notification.Name("showSettings")
    static let openMainWindowAtLaunch = Notification.Name("openMainWindowAtLaunch")
}