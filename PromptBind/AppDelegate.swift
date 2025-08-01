import SwiftUI
import AppKit
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // Sparkle updater
    private var updaterController: SPUStandardUpdaterController!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // With LSUIElement=true, we start as accessory by default
        // No need to set initial policy
        print("AppDelegate: App launched as UI Element (menu bar only)")
        
        // Initialize Sparkle updater
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        print("AppDelegate: Sparkle updater initialized")
        
        // Listen for window lifecycle notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }
    
    // Expose updater for external access
    var updater: SPUUpdater {
        return updaterController.updater
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Show quit warning dialog
        let alert = NSAlert()
        alert.messageText = "Quit PromptBind?"
        alert.informativeText = "If you quit PromptBind, your text expansion prompts will stop working. You can keep them running by closing the window instead, which will run PromptBind in the background."
        alert.alertStyle = .warning
        alert.icon = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Warning")
        
        // Add buttons
        alert.addButton(withTitle: "Run in Background")
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")
        
        // Set default button to "Run in Background"
        alert.buttons[0].keyEquivalent = "\r" // Return key
        alert.buttons[1].keyEquivalent = ""
        alert.buttons[2].keyEquivalent = "\u{1b}" // Escape key
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn: // Run in Background
            print("AppDelegate: User chose to run in background")
            self.runInBackground()
            return .terminateCancel // Don't actually quit
        case .alertSecondButtonReturn: // Quit Anyway
            print("AppDelegate: User chose to quit anyway")
            return .terminateNow
        case .alertThirdButtonReturn: // Cancel
            print("AppDelegate: User cancelled quit")
            return .terminateCancel
        default:
            return .terminateCancel
        }
    }
    
    private func runInBackground() {
        // Close all visible windows but keep the app running
        for window in NSApp.windows {
            if window.isVisible && window.canBecomeMain {
                window.close()
            }
        }
        
        // Ensure we're in accessory mode (menu bar only)
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
        
        print("AppDelegate: App now running in background")
    }
    
    @objc private func windowDidBecomeKey(_ notification: Notification) {
        // When a window becomes key, show in dock
        if NSApp.activationPolicy() != .regular {
            print("AppDelegate: Window opened, showing in dock")
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @objc private func windowWillClose(_ notification: Notification) {
        // Small delay to check if any other windows remain open
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let hasVisibleWindows = NSApp.windows.contains { window in
                window.isVisible && window.canBecomeMain
            }
            
            if !hasVisibleWindows && NSApp.activationPolicy() != .accessory {
                print("AppDelegate: All windows closed, hiding from dock")
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}