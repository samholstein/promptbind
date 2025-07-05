import SwiftUI
import SwiftData
import AppKit // Required for AXIsProcessTrusted

@main
struct PromptBindApp: App {
    let container: ModelContainer
    
    @State private var showingAccessibilityPermissionSheet = false
    @State private var permissionCheckTimer: Timer?

    init() {
        do {
            container = try ModelContainer(for: Prompt.self, Category.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(modelContext: container.mainContext)
                .modelContainer(container)
                .sheet(isPresented: $showingAccessibilityPermissionSheet) {
                    AccessibilityPermissionView()
                }
                .onAppear {
                    checkAccessibilityPermission()
                    // Start polling for permission status
                    permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                        checkAccessibilityPermission()
                    }
                }
                .onDisappear {
                    permissionCheckTimer?.invalidate()
                    permissionCheckTimer = nil
                }
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