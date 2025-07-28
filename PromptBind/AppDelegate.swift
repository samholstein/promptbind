import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // With LSUIElement=true, we start as accessory by default
        // No need to set initial policy
        print("AppDelegate: App launched as UI Element (menu bar only)")
        
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