import AppKit

class WindowDelegate: NSObject, NSWindowDelegate {
    var onWindowWillClose: (() -> Void)?
    
    func windowWillClose(_ notification: Notification) {
        // Prevent the app from terminating when the window closes
        onWindowWillClose?()
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Instead of closing, hide the window
        sender.orderOut(nil)
        onWindowWillClose?()
        return false
    }
}