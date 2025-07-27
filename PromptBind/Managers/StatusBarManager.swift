import AppKit
import SwiftUI

class StatusBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    private var statusBarMenu: NSMenu?
    
    // Callback to handle window visibility changes
    var onShowWindow: (() -> Void)?
    var onHideWindow: (() -> Void)?
    var onQuitApp: (() -> Void)?
    
    @Published var isWindowVisible: Bool = true {
        didSet {
            updateMenuItems()
        }
    }
    
    init() {
        print("StatusBarManager: init() called")
        createStatusBarItem()
    }
    
    private func createStatusBarItem() {
        print("StatusBarManager: createStatusBarItem() called")
        
        // Create the status item with explicit length
        statusItem = NSStatusBar.system.statusItem(withLength: 50)
        
        guard let statusItem = statusItem else {
            print("StatusBarManager: ERROR - Failed to create status item")
            return
        }
        
        guard let button = statusItem.button else {
            print("StatusBarManager: ERROR - Status item has no button")
            return
        }
        
        print("StatusBarManager: Status item and button created successfully")
        
        // Make it as obvious as possible
        button.title = "TEST"
        button.font = NSFont.systemFont(ofSize: 12)
        
        // Try to set icon too
        if let iconPath = Bundle.main.path(forResource: "promptbindicon-statusbar", ofType: "png") {
            print("StatusBarManager: Found icon at path: \(iconPath)")
            
            if let customIcon = NSImage(contentsOfFile: iconPath) {
                print("StatusBarManager: Successfully loaded custom icon")
                customIcon.size = NSSize(width: 16, height: 16)
                button.image = customIcon
                button.imagePosition = .imageLeft
                button.title = "PB"
                print("StatusBarManager: Set both image and title")
            } else {
                print("StatusBarManager: Failed to load custom icon from file")
            }
        } else {
            print("StatusBarManager: Icon file not found, using text only")
        }
        
        // Create simple menu
        statusBarMenu = NSMenu()
        let testItem = NSMenuItem(title: "Test Menu Item", action: nil, keyEquivalent: "")
        statusBarMenu?.addItem(testItem)
        
        let quitItem = NSMenuItem(title: "Quit PromptBind", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        statusBarMenu?.addItem(quitItem)
        
        statusItem.menu = statusBarMenu
        
        print("StatusBarManager: Status bar setup complete with title: '\(button.title ?? "nil")'")
        
        // Debug: Check if the status item is actually visible
        print("StatusBarManager: Status item isVisible: \(statusItem.isVisible)")
        print("StatusBarManager: Status item length: \(statusItem.length)")
        print("StatusBarManager: Button frame: \(button.frame)")
        print("StatusBarManager: Button isHidden: \(button.isHidden)")
        print("StatusBarManager: Button superview: \(button.superview != nil)")
        
        // Force the button to be visible
        button.isHidden = false
        statusItem.isVisible = true
        
        print("StatusBarManager: After forcing visibility - isVisible: \(statusItem.isVisible)")
    }
    
    private func updateMenuItems() {
        // Placeholder for now
    }
    
    @objc private func quitApp() {
        print("StatusBarManager: Quit app called")
        NSApplication.shared.terminate(nil)
    }
    
    deinit {
        print("StatusBarManager: deinit called - STATUS BAR MANAGER IS BEING DEALLOCATED!")
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }
}