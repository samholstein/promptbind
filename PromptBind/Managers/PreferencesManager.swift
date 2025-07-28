import Foundation
import ServiceManagement

class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()
    
    @Published var launchAtStartup: Bool {
        didSet {
            setLaunchAtStartup(launchAtStartup)
        }
    }
    
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }
    
    private let launchAtStartupKey = "launchAtStartup"
    
    private init() {
        // Default to true (launch at startup enabled by default)
        self.launchAtStartup = UserDefaults.standard.object(forKey: launchAtStartupKey) as? Bool ?? true
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        
        // Set initial state if this is first launch
        if UserDefaults.standard.object(forKey: launchAtStartupKey) == nil {
            UserDefaults.standard.set(true, forKey: launchAtStartupKey)
            setLaunchAtStartup(true)
        }
    }
    
    private func setLaunchAtStartup(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: launchAtStartupKey)
        
        do {
            if enabled {
                // Enable launch at startup
                try SMAppService.mainApp.register()
                print("PreferencesManager: Successfully enabled launch at startup")
            } else {
                // Disable launch at startup
                try SMAppService.mainApp.unregister()
                print("PreferencesManager: Successfully disabled launch at startup")
            }
        } catch {
            print("PreferencesManager: Failed to \(enabled ? "enable" : "disable") launch at startup: \(error)")
        }
    }
    
    func syncWithSystem() {
        // Check current system state and update our preference if needed
        let systemState = SMAppService.mainApp.status == .enabled
        if systemState != launchAtStartup {
            launchAtStartup = systemState
        }
    }
}