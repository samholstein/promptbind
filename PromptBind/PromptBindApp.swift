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
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var stripeService = StripeService.shared
    
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
            .environmentObject(subscriptionManager)
            .environmentObject(stripeService)
            .sheet(isPresented: $showingAccessibilityPermissionSheet) {
                AccessibilityPermissionView()
            }
            .onAppear {
                print("PromptBindApp: Main window appeared")
                setupApp()
            }
            .onOpenURL { url in
                handleIncomingURL(url)
            }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 600)
        .defaultPosition(.center)
        
        // MenuBarExtra is now secondary - provides menu access
        MenuBarExtra("PromptBind", systemImage: "keyboard.fill") {
            VStack {
                Button("Prompts") {
                    print("MenuBar: Opening main window")
                    openWindow(id: "main")
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                
                Button("Settings...") {
                    print("MenuBar: Opening settings window")
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
        
        // TEMPORARILY DISABLE SETTINGS WINDOW TO TEST
        // Commenting out the entire settings WindowGroup to see if something else is creating a settings window
        /*
        WindowGroup(id: "settings") {
            SettingsView()
                .environmentObject(cloudKitService)
                .environmentObject(coreDataStack)
                .environmentObject(preferencesManager)
                .environmentObject(subscriptionManager)
                .environmentObject(stripeService)
                .onAppear {
                    print("SettingsView: Settings window appeared - THIS SHOULD NOT HAPPEN")
                }
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 600, height: 650)
        */
        
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
    
    // MARK: - URL Handling for Stripe Checkout
    
    private func handleIncomingURL(_ url: URL) {
        print("PromptBindApp: Received URL: \(url)")
        
        guard url.scheme == "promptbind" else {
            print("PromptBindApp: Ignoring URL with unknown scheme: \(url.scheme ?? "nil")")
            return
        }
        
        switch url.host {
        case "subscription":
            handleSubscriptionURL(url)
        default:
            print("PromptBindApp: Unknown URL host: \(url.host ?? "nil")")
        }
    }
    
    private func handleSubscriptionURL(_ url: URL) {
        print("PromptBindApp: Handling subscription URL: \(url)")
        
        guard let path = url.path.split(separator: "/").first else {
            print("PromptBindApp: No path in subscription URL")
            return
        }
        
        switch String(path) {
        case "success":
            handleSubscriptionSuccess(url)
        case "cancel":
            handleSubscriptionCancel(url)
        default:
            print("PromptBindApp: Unknown subscription path: \(path)")
        }
    }
    
    private func handleSubscriptionSuccess(_ url: URL) {
        print("PromptBindApp: Handling subscription success")
        
        // Extract session_id from URL parameters
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let sessionId = queryItems.first(where: { $0.name == "session_id" })?.value else {
            print("PromptBindApp: No session_id found in success URL")
            showSubscriptionError("Payment completed but could not verify subscription. Please contact support if this persists.")
            return
        }
        
        print("PromptBindApp: Found session ID: \(sessionId)")
        
        // Show success message immediately
        showSubscriptionSuccess("Payment successful! Verifying your subscription...")
        
        // Verify the subscription with Stripe
        Task { @MainActor in
            do {
                print("PromptBindApp: Verifying subscription with Stripe for session: \(sessionId)")
                
                // Use the new Stripe verification method
                let subscriptionData = try await stripeService.verifyCheckoutSession(sessionId)
                
                print("PromptBindApp: Subscription verified - Status: \(subscriptionData.status)")
                
                // Save subscription to Core Data (will sync via CloudKit)
                let deviceId = DeviceIdentificationService.shared.getDeviceID()
                let _ = coreDataStack.saveSubscription(
                    deviceId: deviceId,
                    status: subscriptionData.status,
                    customerId: subscriptionData.customerId,
                    stripeSubscriptionId: subscriptionData.subscriptionId,
                    expiresAt: subscriptionData.expiresAt
                )
                
                // Update subscription manager
                subscriptionManager.updateFromStripeData(subscriptionData)
                
                // Show success with retry option
                showSubscriptionSuccessWithDetails(subscriptionData)
                
            } catch {
                print("PromptBindApp: Error verifying subscription: \(error)")
                showSubscriptionErrorWithRetry(sessionId, error)
            }
        }
    }
    
    private func handleSubscriptionCancel(_ url: URL) {
        print("PromptBindApp: Handling subscription cancellation")
        showSubscriptionInfo("Subscription upgrade was cancelled. You can try again anytime!")
    }
    
    // MARK: - Enhanced User Notifications
    
    private func showSubscriptionSuccessWithDetails(_ subscriptionData: SubscriptionData) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Welcome to PromptBind Pro!"
            
            let statusMessage = subscriptionData.status.lowercased() == "trialing" ? 
                "Your 30-day free trial is now active. You have unlimited access to all Pro features." :
                "Your subscription is now active. You have unlimited access to all Pro features."
                
            alert.informativeText = statusMessage + "\n\nYour subscription will automatically sync to your other devices signed into the same iCloud account."
            alert.alertStyle = .informational
            alert.icon = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Success")
            alert.addButton(withTitle: "Get Started")
            alert.runModal()
        }
    }
    
    private func showSubscriptionErrorWithRetry(_ sessionId: String, _ error: Error) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Subscription Verification Issue"
            alert.informativeText = "Your payment was processed successfully, but we're having trouble verifying your subscription.\n\nError: \(error.localizedDescription)\n\nThis usually resolves automatically within a few minutes. You can also try refreshing your subscription status in Settings."
            alert.alertStyle = .warning
            alert.icon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")
            alert.addButton(withTitle: "Retry Now")
            alert.addButton(withTitle: "Check Later")
            
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                // Retry verification
                Task { @MainActor in
                    do {
                        let subscriptionData = try await self.stripeService.verifyCheckoutSession(sessionId)
                        self.subscriptionManager.updateFromStripeData(subscriptionData)
                        self.showSubscriptionSuccessWithDetails(subscriptionData)
                    } catch {
                        self.showSubscriptionError("Retry failed: \(error.localizedDescription). Please check Settings → Subscription → Refresh Status in a few minutes.")
                    }
                }
            }
        }
    }
    
    private func showSubscriptionSuccess(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Subscription Success"
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.icon = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Success")
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    private func showSubscriptionError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Subscription Error"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.icon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Error")
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    private func showSubscriptionInfo(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Subscription Update"
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

extension Notification.Name {
    static let exportData = Notification.Name("exportData")
    static let importData = Notification.Name("importData")
    static let showSettings = Notification.Name("showSettings")
    static let openMainWindowAtLaunch = Notification.Name("openMainWindowAtLaunch")
}