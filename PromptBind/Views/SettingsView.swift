import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingCloudKitHelp = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 10)
            
            // iCloud Section
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("iCloud Sync")
                            .font(.headline)
                        Spacer()
                        Button("Help") {
                            showingCloudKitHelp = true
                        }
                        .font(.caption)
                    }
                    
                    HStack {
                        Image(systemName: cloudKitService.isSignedIn ? "icloud" : "icloud.slash")
                            .foregroundColor(cloudKitService.isSignedIn ? .blue : .orange)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Status: \(cloudKitService.accountStatus.description)")
                                .font(.body)
                            
                            if cloudKitService.isSignedIn {
                                Text("Your prompts will sync across all your devices")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Sign into iCloud in System Preferences to enable sync")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if !cloudKitService.isSignedIn {
                            Button("Open System Preferences") {
                                openSystemPreferences()
                            }
                            .controlSize(.small)
                        } else {
                            Button("Refresh Status") {
                                cloudKitService.checkAccountStatus()
                            }
                            .controlSize(.small)
                        }
                    }
                    
                    if let errorMessage = cloudKitService.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding()
            }
            
            // App Settings Section
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("General")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Launch at startup", isOn: .constant(false))
                            .disabled(true) // Will implement later
                        
                        Toggle("Show in menu bar only", isOn: .constant(false))
                            .disabled(true) // Will implement later
                        
                        HStack {
                            Text("Trigger monitoring:")
                            Spacer()
                            Text("Active")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    }
                }
                .padding()
            }
            
            // About Section
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("About")
                        .font(.headline)
                    
                    HStack {
                        Text("Version:")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build:")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 500, height: 400)
        .alert("iCloud Sync Help", isPresented: $showingCloudKitHelp) {
            Button("OK") { }
        } message: {
            Text("To enable iCloud sync:\n\n1. Open System Preferences\n2. Go to Apple ID\n3. Ensure iCloud Drive is enabled\n4. Sign in with your Apple ID\n\nOnce enabled, your prompts will automatically sync across all your Mac devices.")
        }
    }
    
    private func openSystemPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane")!
        NSWorkspace.shared.open(url)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(CloudKitService())
    }
}