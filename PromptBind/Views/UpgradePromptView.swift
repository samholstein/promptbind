import SwiftUI

struct UpgradePromptView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)
            
            // Main content
            VStack(spacing: 20) {
                // Icon
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                
                // Title
                Text("Upgrade to PromptBind Pro")
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                // Subtitle
                Text("You've reached the 5-prompt limit for free accounts")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                // Features list
                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "infinity", title: "Unlimited Prompts", subtitle: "Create as many text expansions as you need")
                    FeatureRow(icon: "icloud.fill", title: "iCloud Sync", subtitle: "Access your prompts across all your devices")
                    FeatureRow(icon: "square.and.arrow.down", title: "Import/Export", subtitle: "Backup and share your prompt libraries")
                    FeatureRow(icon: "sparkles", title: "Future Features", subtitle: "Get access to new Pro features as they're released")
                }
                .padding(.horizontal)
                
                // Pricing
                VStack(spacing: 8) {
                    HStack(alignment: .bottom, spacing: 4) {
                        Text("$4.99")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("/month")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Cancel anytime")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Current status
                VStack(spacing: 8) {
                    HStack {
                        Text("Current Usage:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(subscriptionManager.promptCount)/5 prompts")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    ProgressView(value: Double(subscriptionManager.promptCount), total: 5)
                        .progressViewStyle(LinearProgressViewStyle(tint: .orange))
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 12) {
                Button("Upgrade to Pro") {
                    // TODO: Start subscription flow
                    handleUpgradeAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button("Maybe Later") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 400, height: 600)
        .background(Color(.windowBackgroundColor))
    }
    
    private func handleUpgradeAction() {
        print("UpgradePromptView: User wants to upgrade - TODO: Implement Stripe flow")
        
        // TODO: Phase 2 - Launch Stripe checkout
        // For now, let's add a temporary Pro activation for testing
        #if DEBUG
        subscriptionManager.activateSubscription()
        dismiss()
        #endif
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

struct UpgradePromptView_Previews: PreviewProvider {
    static var previews: some View {
        UpgradePromptView()
            .environmentObject(SubscriptionManager.shared)
    }
}