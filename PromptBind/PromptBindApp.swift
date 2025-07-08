import SwiftUI
import SwiftData
import AppKit // Required for AXIsProcessTrusted

@main
struct PromptBindApp: App {
    let container: ModelContainer
    
    @State private var showingAccessibilityPermissionSheet = false
    @State private var permissionCheckTimer: Timer?
    @StateObject private var statusBarManager = StatusBarManager()
    @State private var isWindowVisible = true
    
    // Keep trigger monitor at app level to ensure it persists
    @State private var triggerMonitor: TriggerMonitorService?

    init() {
        do {
            container = try ModelContainer(for: Prompt.self, Category.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(modelContext: container.mainContext, triggerMonitor: triggerMonitor)
                .modelContainer(container)
                .sheet(isPresented: $showingAccessibilityPermissionSheet) {
                    AccessibilityPermissionView()
                }
                .onAppear {
                    // Initialize trigger monitor if not already created
                    if triggerMonitor == nil {
                        triggerMonitor = TriggerMonitorService(modelContext: container.mainContext)
                    }
                    
                    checkAccessibilityPermission()
                    // Start polling for permission status
                    permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                        checkAccessibilityPermission()
                    }
                    
                    // Set up status bar callbacks
                    setupStatusBarCallbacks()
                    
                    // Start trigger monitoring at app level
                    triggerMonitor?.startMonitoring()
                    
                    // Update status bar state - initially window is visible
                    statusBarManager.isWindowVisible = true
                    
                    // Ensure the window is visible and the app is in the foreground
                    DispatchQueue.main.async {
                        NSApplication.shared.setActivationPolicy(.regular)
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        if let window = NSApplication.shared.windows.first {
                            window.makeKeyAndOrderFront(nil)
                        }
                    }
                }
                .onDisappear {
                    permissionCheckTimer?.invalidate()
                    permissionCheckTimer = nil
                    
                    // Update status bar state
                    statusBarManager.isWindowVisible = false
                    updateAppActivationPolicy(windowVisible: false)
                }
                .onReceive(NotificationCenter.default.publisher(for: .windowWillHide)) { _ in
                    hideWindow()
                }
        }
        .windowResizability(.contentSize)
        .commands {
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
        .defaultSize(width: 800, height: 600)
    }
    
    private func setupStatusBarCallbacks() {
        print("PromptBindApp: Setting up status bar callbacks...")
        statusBarManager.onShowWindow = {
            print("PromptBindApp: Status bar show window callback")
            showWindow()
        }
        
        statusBarManager.onHideWindow = {
            print("PromptBindApp: Status bar hide window callback")
            hideWindow()
        }
        
        statusBarManager.onQuitApp = {
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
        
        statusBarManager.isWindowVisible = true
    }
    
    private func hideWindow() {
        print("PromptBindApp: Hide window called")
        // Hide all windows
        NSApplication.shared.windows.forEach { window in
            window.orderOut(nil)
        }
        
        statusBarManager.isWindowVisible = false
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
        if !isTrusted && !showingAccessibilityPermissionSheet {
            showingAccessibilityPermissionSheet = true
        } else if isTrusted && showingAccessibilityPermissionSheet {
            showingAccessibilityPermissionSheet = false
            // Invalidate timer if permission is granted and sheet is dismissed
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
        }
    }
}

extension Notification.Name {
    static let exportData = Notification.Name("exportData")
    static let importData = Notification.Name("importData")
    static let windowWillHide = Notification.Name("windowWillHide")
}