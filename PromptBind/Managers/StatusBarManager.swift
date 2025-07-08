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
        print("StatusBarManager: Initializing...")
        setupStatusBar()
    }
    
    private func setupStatusBar() {
        print("StatusBarManager: Setting up status bar...")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            // Try to load the custom icon first
            if let iconPath = Bundle.main.path(forResource: "promptbindicon-statusbar", ofType: "png"),
               let customIcon = NSImage(contentsOfFile: iconPath) {
                // Resize the icon to be appropriate for status bar (18x18 points)
                customIcon.size = NSSize(width: 18, height: 18)
                button.image = customIcon
                button.image?.isTemplate = true
                print("StatusBarManager: Custom status bar icon loaded")
            } else {
                // Fallback to system icon
                button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "PromptBind")
                button.image?.isTemplate = true
                print("StatusBarManager: Using fallback system icon")
            }
        } else {
            print("StatusBarManager: ERROR - Could not get status bar button")
        }
        
        setupMenu()
    }
    
    private func setupMenu() {
        print("StatusBarManager: Setting up menu...")
        statusBarMenu = NSMenu()
        
        // Show/Hide menu item (will be updated dynamically)
        let showHideItem = NSMenuItem(title: "Show PromptBind", action: #selector(toggleWindow), keyEquivalent: "")
        showHideItem.target = self
        showHideItem.tag = 1
        statusBarMenu?.addItem(showHideItem)
        
        // Separator
        statusBarMenu?.addItem(NSMenuItem.separator())
        
        // Quit menu item
        let quitItem = NSMenuItem(title: "Quit PromptBind", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        statusBarMenu?.addItem(quitItem)
        
        statusItem?.menu = statusBarMenu
        print("StatusBarManager: Menu configured with \(statusBarMenu?.items.count ?? 0) items")
    }
    
    private func updateMenuItems() {
        guard let menu = statusBarMenu else { return }
        
        // Update the show/hide menu item
        if let showHideItem = menu.item(withTag: 1) {
            if isWindowVisible {
                showHideItem.title = "Hide PromptBind"
            } else {
                showHideItem.title = "Show PromptBind"
            }
        }
    }
    
    @objc private func toggleWindow() {
        print("StatusBarManager: Toggle window called")
        if isWindowVisible {
            onHideWindow?()
        } else {
            onShowWindow?()
        }
    }
    
    @objc private func quitApp() {
        print("StatusBarManager: Quit app called")
        onQuitApp?()
    }
    
    deinit {
        print("StatusBarManager: Deinitializing...")
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }
}