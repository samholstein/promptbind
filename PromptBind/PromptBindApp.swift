import SwiftUI
import CoreData
import AppKit // Required for AXIsProcessTrusted

@main
struct PromptBindApp: App {
    @StateObject private var coreDataStack = CoreDataStack.shared
    @StateObject private var cloudKitService = CloudKitService()
    @StateObject private var windowManager = WindowManager.shared
    
    @State private var showingAccessibilityPermissionSheet = false
    @State private var permissionCheckTimer: Timer?
    @State private var statusBarManager: StatusBarManager?
    @State private var isWindowVisible = true
    
    // Keep trigger monitor at app level to ensure it persists
    @State private var triggerMonitor: TriggerMonitorService?

    var body: some Scene {
        WindowGroup {
            ContentView(
                viewContext: coreDataStack.viewContext,
                triggerMonitor: triggerMonitor,
                cloudKitService: cloudKitService
            )
            .environment(\.managedObjectContext, coreDataStack.viewContext)
            .environmentObject(coreDataStack)
            .environmentObject(cloudKitService)
            .environmentObject(windowManager)
            .sheet(isPresented: $showingAccessibilityPermissionSheet) {
                AccessibilityPermissionView()
            }
            .onAppear {
                print("PromptBindApp: onAppear called")
                
                // Initialize trigger monitor if not already created
                if triggerMonitor == nil {
                    triggerMonitor = TriggerMonitorService(viewContext: coreDataStack.viewContext)
                    print("PromptBindApp: Created TriggerMonitorService")
                }
                
                // Check accessibility permission once
                checkAccessibilityPermission()
                
                // Only start polling if permission is not granted
                if !AXIsProcessTrusted() {
                    // Start polling for permission status
                    permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                        checkAccessibilityPermission()
                    }
                } else {
                    // Permission is already granted, start monitoring
                    triggerMonitor?.startMonitoring()
                }
                
                // Set up window first
                DispatchQueue.main.async {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                
                // Create status bar AFTER app is fully initialized
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    print("PromptBindApp: Creating StatusBarManager after delay")
                    if statusBarManager == nil {
                        statusBarManager = StatusBarManager()
                        print("PromptBindApp: StatusBarManager created: \(statusBarManager != nil)")
                        setupStatusBarCallbacks()
                    }
                }
            }
            .onDisappear {
                print("PromptBindApp: onDisappear called")
                permissionCheckTimer?.invalidate()
                permissionCheckTimer = nil
                
                // Update status bar state
                statusBarManager?.isWindowVisible = false
                updateAppActivationPolicy(windowVisible: false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .windowWillHide)) { _ in
                hideWindow()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
                windowManager.openSettingsWindow()
            }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 600)
        
        // Dedicated Settings Window
        WindowGroup("Settings") {
            SettingsView()
                .environmentObject(cloudKitService)
                .environmentObject(coreDataStack)
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 500, height: 400)
        
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    windowManager.openSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            
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
    
    private func setupStatusBarCallbacks() {
        print("PromptBindApp: Setting up status bar callbacks...")
        statusBarManager?.onShowWindow = {
            print("PromptBindApp: Status bar show window callback")
            self.showWindow()
        }
        
        statusBarManager?.onHideWindow = {
            print("PromptBindApp: Status bar hide window callback")
            self.hideWindow()
        }
        
        statusBarManager?.onQuitApp = {
            print("PromptBindApp: Status bar quit app callback")
            NSApplication.shared.terminate(nil)
        }
    }
    
    private func showWindow() {
        print("PromptBindApp: Show window called")
        // Set activation policy to regular first
        updateAppActivationPolicy(windowVisible: true)
        
        // Activate the app and show the window
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Find and show the main window
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
            print("PromptBindApp: Window made key and front")
        } else {
            print("PromptBindApp: ERROR - No window found")
        }
        
        statusBarManager?.isWindowVisible = true
    }
    
    private func hideWindow() {
        print("PromptBindApp: Hide window called")
        // Hide main windows but keep settings window
        NSApplication.shared.windows.forEach { window in
            if window.title != "Settings" && window.contentViewController is NSHostingController<ContentView> {
                window.orderOut(nil)
            }
        }
        
        statusBarManager?.isWindowVisible = false
        updateAppActivationPolicy(windowVisible: false)
    }
    
    private func updateAppActivationPolicy(windowVisible: Bool) {
        print("PromptBindApp: Updating activation policy - windowVisible: \(windowVisible)")
        if windowVisible {
            // Show in dock and command-tab when window is visible
            NSApplication.shared.setActivationPolicy(.regular)
            print("PromptBindApp: Set activation policy to regular")
        } else {
            // Hide from dock and command-tab when window is hidden
            NSApplication.shared.setActivationPolicy(.accessory)
            print("PromptBindApp: Set activation policy to accessory")
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
            // Stop polling and start monitoring
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
            triggerMonitor?.startMonitoring()
        }
    }
}

extension Notification.Name {
    static let exportData = Notification.Name("exportData")
    static let importData = Notification.Name("importData")
    static let windowWillHide = Notification.Name("windowWillHide")
    static let showSettings = Notification.Name("showSettings")
}