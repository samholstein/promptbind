import SwiftUI
import AppKit // For NSWorkspace

struct AccessibilityPermissionView: View {
    // This view doesn't directly control the polling or dismissal.
    // It relies on the parent view (PromptBindApp's sheet presentation) to handle that.

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard.badge.eye") // More relevant icon
                .font(.system(size: 50))
                .foregroundColor(.accentColor)

            Text("Accessibility Access Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("PromptBind needs Accessibility permissions to monitor your keystrokes for trigger phrases and perform text replacements system-wide.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Text("Please grant access in:\nSystem Settings → Privacy & Security → Accessibility.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Open System Settings") {
                openAccessibilitySettings()
            }
            .padding()
            .controlSize(.large)

            // The "Not Now" or dismiss is handled by the sheet's presentation logic
            // in PromptBindApp, which polls and dismisses when permission is granted.
            // A manual dismiss button here might be confusing if polling is active.
            // If you want a manual dismiss, you'd need a binding to control the sheet.
        }
        .padding(30)
        .frame(width: 400)
    }

    private func openAccessibilitySettings() {
        // For macOS 13 Ventura and later:
        // x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?path=ACCESSIBILITY
        // For older macOS versions (like Big Sur 11.0+ as per TRD):
        // x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility
        
        // Let's use the one that works more broadly or for newer systems if possible,
        // but the TRD specified one should be fine for macOS 11+ target.
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

struct AccessibilityPermissionView_Previews: PreviewProvider {
    static var previews: some View {
        AccessibilityPermissionView()
    }
}