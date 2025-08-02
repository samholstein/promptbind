import SwiftUI
import AppKit // For NSWorkspace

struct AccessibilityPermissionView: View {
    var onComplete: (() -> Void)?
    
    @State private var isChecking = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Accessibility Access Required")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("PromptBind needs Accessibility permissions to monitor your keystrokes for trigger phrases and perform text replacements system-wide.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Text("Please grant access in:\nSystem Settings → Privacy & Security → Accessibility.")
                .font(.body)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 12) {
                Button("Open System Settings") {
                    openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
                
                Button(isChecking ? "Checking..." : "I've Granted Permission") {
                    checkPermissions()
                }
                .disabled(isChecking)
            }
            
            Text("PromptBind will not function without these permissions.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .padding(30)
        .frame(width: 450, height: 350)
    }
    
    private func openAccessibilitySettings() {
        // Updated for modern macOS versions
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func checkPermissions() {
        isChecking = true
        
        // Small delay to allow for permission changes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isChecking = false
            
            if AXIsProcessTrusted() {
                print("AccessibilityPermissionView: Permissions granted!")
                onComplete?()
            } else {
                print("AccessibilityPermissionView: Permissions still not granted")
                // Could show an alert here
            }
        }
    }
}

struct AccessibilityPermissionView_Previews: PreviewProvider {
    static var previews: some View {
        AccessibilityPermissionView()
    }
}