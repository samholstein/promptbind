import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowStatusDebouncer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set initial activation policy
        updateActivationPolicy()
        
        // Listen for window open/close notifications
        NotificationCenter.default.addObserver(self, selector: #selector(windowVisibilityChanged), name: NSWindow.didBecomeKeyNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowVisibilityChanged), name: NSWindow.willCloseNotification, object: nil)
    }
    
    @objc private func windowVisibilityChanged() {
        // Debounce to handle rapid open/close events (e.g., window tabbing)
        windowStatusDebouncer?.invalidate()
        windowStatusDebouncer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            self?.updateActivationPolicy()
        }
    }
    
    private func hasVisibleWindows() -> Bool {
        // Check if there are any visible windows, excluding the status bar item itself
        return NSApplication.shared.windows.contains { $0.isVisible && $0.canBecomeMain }
    }
    
    private func updateActivationPolicy() {
        if hasVisibleWindows() {
            print("AppDelegate: Windows are visible, setting policy to .regular")
            NSApp.setActivationPolicy(.regular)
        } else {
            print("AppDelegate: No visible windows, setting policy to .accessory")
            NSApp.setActivationPolicy(.accessory)
            // When we hide the last window, we need to manually activate another app
            // so our app's menu bar disappears.
            NSWorkspace.shared.runningApplications.first { $0 != NSRunningApplication.current && $0.isActive }?.activate()
        }
    }
}