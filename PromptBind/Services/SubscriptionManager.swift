import Foundation
import Combine

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    // MARK: - Published Properties
    @Published var subscriptionStatus: SubscriptionStatus = .free
    @Published var promptCount: Int = 0
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    @Published var lastSyncDate: Date?
    @Published var isCheckingStripeStatus: Bool = false
    
    // MARK: - Private Properties
    private let maxFreePrompts = 5
    private var cancellables = Set<AnyCancellable>()
    
    // Periodic checking timer
    private var periodicCheckTimer: Timer?
    private let checkInterval: TimeInterval = 24 * 60 * 60 // 24 hours
    
    // MARK: - Subscription Status (Simplified - no local trial logic)
    enum SubscriptionStatus: Equatable {
        case free
        case subscribed(expiresAt: Date?)
        case expired
        
        var isActive: Bool {
            switch self {
            case .free:
                return false
            case .subscribed:
                return true
            case .expired:
                return false
            }
        }
        
        var displayName: String {
            switch self {
            case .free:
                return "Free"
            case .subscribed:
                return "Pro"
            case .expired:
                return "Expired"
            }
        }
    }
    
    private init() {
        print("SubscriptionManager: Initializing...")
        
        // Load subscription from Core Data first (CloudKit-synced data)
        loadSubscriptionFromCoreData()
        
        // Fallback to UserDefaults if no Core Data subscription exists
        if case .free = subscriptionStatus {
            loadSubscriptionFromUserDefaults()
        }
        
        print("SubscriptionManager: Initialized with status: \(subscriptionStatus), count: \(promptCount)")
        
        // Refresh prompt count from Core Data on startup
        refreshPromptCount()
        
        // Start periodic subscription checking
        startPeriodicChecking()
        
        // Check subscription status on launch (after a delay to let things settle)
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            await checkSubscriptionStatusFromStripe()
        }
    }
    
    // MARK: - Core Data Integration
    
    /// Loads subscription status from Core Data (CloudKit-synced)
    private func loadSubscriptionFromCoreData() {
        print("SubscriptionManager: Loading subscription from Core Data...")
        
        // Get all subscriptions and find the most recent active one
        let allSubscriptions = CoreDataStack.shared.getAllSubscriptions()
        
        // Find the most recent active subscription across all devices
        let activeSubscription = allSubscriptions
            .filter { $0.isActiveSubscription }
            .sorted { $0.subscriptionUpdatedAt > $1.subscriptionUpdatedAt }
            .first
        
        if let subscription = activeSubscription {
            print("SubscriptionManager: Found active subscription from device: \(subscription.subscriptionDeviceId.prefix(8))...")
            
            let stripeData = SubscriptionData(
                status: subscription.subscriptionStatus,
                expiresAt: subscription.subscriptionExpiresAt,
                customerId: subscription.subscriptionCustomerId,
                subscriptionId: subscription.subscriptionStripeSubscriptionId
            )
            
            updateFromStripeData(stripeData)
            lastSyncDate = subscription.subscriptionUpdatedAt
        } else {
            print("SubscriptionManager: No active subscription found in Core Data")
        }
    }
    
    /// Saves current subscription status to Core Data (will sync via CloudKit)
    private func saveSubscriptionToCoreData() {
        print("SubscriptionManager: Saving subscription to Core Data...")
        
        let deviceId = DeviceIdentificationService.shared.getDeviceID()
        let status: String
        
        switch subscriptionStatus {
        case .free:
            status = "free"
        case .subscribed:
            status = "active" // Use Stripe terminology
        case .expired:
            status = "expired"
        }
        
        // Get existing device subscription from Core Data to preserve Stripe IDs
        let existingSubscription = CoreDataStack.shared.getDeviceSubscription()
        
        let _ = CoreDataStack.shared.saveSubscription(
            deviceId: deviceId,
            status: status,
            customerId: existingSubscription?.subscriptionCustomerId,
            stripeSubscriptionId: existingSubscription?.subscriptionStripeSubscriptionId,
            expiresAt: {
                if case .subscribed(let expiresAt) = subscriptionStatus {
                    return expiresAt
                }
                return nil
            }()
        )
        
        lastSyncDate = Date()
        print("SubscriptionManager: Saved subscription to Core Data (will sync via CloudKit)")
    }
    
    // MARK: - CloudKit Sync
    
    /// Syncs subscription status from CloudKit (called when CloudKit import completes)
    func syncSubscriptionFromCloudKit() {
        print("SubscriptionManager: Syncing subscription from CloudKit...")
        
        let previousStatus = subscriptionStatus
        
        // Reload from Core Data (which now has updated CloudKit data)
        loadSubscriptionFromCoreData()
        
        // Check if status changed due to CloudKit sync
        if previousStatus != subscriptionStatus {
            print("SubscriptionManager: Subscription status changed from CloudKit sync: \(previousStatus) → \(subscriptionStatus)")
            
            // If we gained Pro access from another device, we might want to notify the user
            if !previousStatus.isActive && subscriptionStatus.isActive {
                print("SubscriptionManager: Pro access gained from CloudKit sync!")
            }
        }
    }
    
    /// Resolves conflicts when multiple devices have different subscription states
    private func resolveSubscriptionConflicts() {
        print("SubscriptionManager: Resolving subscription conflicts...")
        
        let allSubscriptions = CoreDataStack.shared.getAllSubscriptions()
        
        // Find the most authoritative subscription (most recent with Stripe data)
        let authoritativeSubscription = allSubscriptions
            .filter { subscription in
                // Prioritize subscriptions with Stripe data
                return subscription.subscriptionCustomerId != nil && 
                       subscription.subscriptionStripeSubscriptionId != nil
            }
            .sorted { lhs, rhs in
                // Sort by update date, but prioritize active subscriptions
                if lhs.isActiveSubscription != rhs.isActiveSubscription {
                    return lhs.isActiveSubscription && !rhs.isActiveSubscription
                }
                return lhs.subscriptionUpdatedAt > rhs.subscriptionUpdatedAt
            }
            .first
        
        if let authoritative = authoritativeSubscription {
            print("SubscriptionManager: Using authoritative subscription from device: \(authoritative.subscriptionDeviceId.prefix(8))...")
            
            let stripeData = SubscriptionData(
                status: authoritative.subscriptionStatus,
                expiresAt: authoritative.subscriptionExpiresAt,
                customerId: authoritative.subscriptionCustomerId,
                subscriptionId: authoritative.subscriptionStripeSubscriptionId
            )
            
            updateFromStripeData(stripeData)
        }
    }
    
    // MARK: - Periodic Status Checking
    
    /// Starts periodic subscription status checking (every 24 hours)
    private func startPeriodicChecking() {
        print("SubscriptionManager: Starting periodic subscription checking (every 24 hours)")
        
        periodicCheckTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkSubscriptionStatusFromStripe()
            }
        }
    }
    
    /// Checks subscription status with Stripe (if we have a customer ID)
    func checkSubscriptionStatusFromStripe() async {
        guard !isCheckingStripeStatus else {
            print("SubscriptionManager: Already checking Stripe status, skipping...")
            return
        }
        
        print("SubscriptionManager: Checking subscription status from Stripe...")
        
        isCheckingStripeStatus = true
        lastError = nil
        
        defer {
            isCheckingStripeStatus = false
        }
        
        do {
            if let subscriptionData = try await StripeService.shared.checkDeviceSubscriptionStatus() {
                print("SubscriptionManager: Retrieved subscription status from Stripe: \(subscriptionData.status)")
                
                // Phase 6: Additional validation
                if let customerId = subscriptionData.customerId, customerId.isEmpty {
                    print("⚠️ WARNING: Empty customer ID from Stripe")
                }
                
                // Update local status with Stripe data
                updateFromStripeData(subscriptionData)
                
                // Save to Core Data (will sync to other devices via CloudKit)
                saveSubscriptionToCoreData()
                
                // Update device subscription with fresh Stripe data
                if let customerId = subscriptionData.customerId,
                   let subscriptionId = subscriptionData.subscriptionId {
                    
                    let deviceId = DeviceIdentificationService.shared.getDeviceID()
                    let _ = CoreDataStack.shared.saveSubscription(
                        deviceId: deviceId,
                        status: subscriptionData.status,
                        customerId: customerId,
                        stripeSubscriptionId: subscriptionId,
                        expiresAt: subscriptionData.expiresAt
                    )
                }
                
                print("✅ Successfully updated subscription from Stripe")
                
            } else {
                print("SubscriptionManager: No subscription found in Stripe for this device")
                // This is not necessarily an error - user might be on free plan
            }
            
        } catch {
            print("❌ SubscriptionManager: Error checking Stripe subscription status: \(error)")
            
            // Phase 7: Improved error messages
            if error.localizedDescription.contains("network") {
                lastError = "Unable to check subscription status. Please check your internet connection."
            } else if error.localizedDescription.contains("unauthorized") {
                lastError = "Subscription verification failed. Please try upgrading again."
            } else {
                lastError = "Failed to check subscription status: \(error.localizedDescription)"
            }
        }
    }
    
    /// Manually refresh subscription status (for user-triggered refresh)
    func refreshSubscriptionStatus() async {
        print("SubscriptionManager: Manual subscription refresh requested")
        
        // First, sync from CloudKit
        syncSubscriptionFromCloudKit()
        
        // Then check with Stripe
        await checkSubscriptionStatusFromStripe()
    }
    
    // MARK: - Public Methods
    
    /// Force refresh the prompt count from Core Data
    func refreshPromptCount() {
        let count = CoreDataStack.shared.promptCount()
        if count != promptCount {
            updatePromptCount(count)
        }
    }
    
    /// Updates the current prompt count
    func updatePromptCount(_ count: Int) {
        print("SubscriptionManager: Updating prompt count from \(promptCount) to \(count)")
        promptCount = count
        saveSubscriptionState() // Save to UserDefaults for quick access
    }
    
    /// Checks if user can create a new prompt
    func canCreatePrompt() -> Bool {
        let result: Bool
        switch subscriptionStatus {
        case .free:
            result = promptCount < maxFreePrompts
            print("SubscriptionManager: Can create prompt (free): \(result) (\(promptCount) < \(maxFreePrompts))")
            
            // Phase 6: Validation check
            if promptCount < 0 {
                print("⚠️ WARNING: Negative prompt count detected: \(promptCount)")
                lastError = "Invalid prompt count detected. Please refresh."
            }
            if promptCount > 1000 {
                print("⚠️ WARNING: Suspiciously high prompt count: \(promptCount)")
            }
            
        case .subscribed:
            result = true
            print("SubscriptionManager: Can create prompt (subscribed): true")
        case .expired:
            result = false
            print("SubscriptionManager: Can create prompt (expired): false")
        }
        
        // Phase 6: Log for testing
        print("📊 Subscription Check - Status: \(subscriptionStatus.displayName), Count: \(promptCount), Can Create: \(result)")
        
        return result
    }
    
    /// Checks if user is at the free limit
    func isAtFreeLimit() -> Bool {
        guard case .free = subscriptionStatus else { return false }
        let atLimit = promptCount >= maxFreePrompts
        print("SubscriptionManager: Is at free limit: \(atLimit) (\(promptCount) >= \(maxFreePrompts))")
        return atLimit
    }
    
    /// Checks if user has access to pro features (like import)
    func hasProAccess() -> Bool {
        let hasAccess = subscriptionStatus.isActive
        print("SubscriptionManager: Has pro access: \(hasAccess) (status: \(subscriptionStatus))")
        return hasAccess
    }
    
    /// Gets the remaining free prompts
    func remainingFreePrompts() -> Int {
        guard case .free = subscriptionStatus else { return 0 }
        return max(0, maxFreePrompts - promptCount)
    }
    
    // MARK: - Subscription Management (Stripe-driven)
    
    /// Updates subscription status from Stripe data
    func updateFromStripeData(_ stripeData: SubscriptionData) {
        let previousStatus = subscriptionStatus
        
        print("SubscriptionManager: Updating from Stripe data - Status: \(stripeData.status)")
        
        // Phase 6: Validate Stripe data
        guard !stripeData.status.isEmpty else {
            print("⚠️ WARNING: Empty Stripe status received")
            lastError = "Invalid subscription data received from Stripe"
            return
        }
        
        switch stripeData.status.lowercased() {
        case "active", "trialing":
            // Both active and trialing subscriptions get Pro access
            // Stripe handles the trial logic internally
            subscriptionStatus = .subscribed(expiresAt: stripeData.expiresAt)
            print("SubscriptionManager: Set to subscribed (Stripe status: \(stripeData.status))")
        case "canceled", "cancelled", "past_due", "unpaid", "incomplete", "incomplete_expired":
            subscriptionStatus = .expired
            print("SubscriptionManager: Set to expired (Stripe status: \(stripeData.status))")
        default:
            subscriptionStatus = .free
            print("SubscriptionManager: Set to free (Stripe status: \(stripeData.status))")
        }
        
        // Phase 6: Log status changes
        if previousStatus != subscriptionStatus {
            print("🔄 STATUS CHANGE: \(previousStatus.displayName) → \(subscriptionStatus.displayName)")
            saveSubscriptionState() // Quick save to UserDefaults
            saveSubscriptionToCoreData() // Save to Core Data (CloudKit sync)
            
            // Clear any previous errors on successful status change
            lastError = nil
        }
    }
    
    /// Activates a subscription (called after successful Stripe payment)
    func activateSubscription(expiresAt: Date? = nil) {
        print("SubscriptionManager: Activating subscription")
        subscriptionStatus = .subscribed(expiresAt: expiresAt)
        saveSubscriptionState()
        saveSubscriptionToCoreData()
    }
    
    /// Expires the current subscription
    func expireSubscription() {
        print("SubscriptionManager: Expiring subscription")
        subscriptionStatus = .expired
        saveSubscriptionState()
        saveSubscriptionToCoreData()
    }
    
    /// Resets to free tier (useful for testing)
    func resetToFree() {
        print("SubscriptionManager: Resetting to free tier")
        subscriptionStatus = .free
        saveSubscriptionState()
        saveSubscriptionToCoreData()
    }
    
    // MARK: - UserDefaults Persistence (for quick access)
    
    private func loadSubscriptionFromUserDefaults() {
        let defaults = UserDefaults.standard
        
        // Load subscription status
        if let statusData = defaults.data(forKey: "subscriptionStatus"),
           let status = try? JSONDecoder().decode(SubscriptionStatusData.self, from: statusData) {
            subscriptionStatus = status.toSubscriptionStatus()
        }
        
        // Load prompt count (will be refreshed from Core Data)
        promptCount = defaults.integer(forKey: "promptCount")
        
        print("SubscriptionManager: Loaded state from UserDefaults - Status: \(subscriptionStatus), Count: \(promptCount)")
    }
    
    private func saveSubscriptionState() {
        let defaults = UserDefaults.standard
        
        // Save subscription status
        let statusData = SubscriptionStatusData.from(subscriptionStatus)
        if let encoded = try? JSONEncoder().encode(statusData) {
            defaults.set(encoded, forKey: "subscriptionStatus")
        }
        
        // Save prompt count
        defaults.set(promptCount, forKey: "promptCount")
        
        print("SubscriptionManager: Saved state to UserDefaults - Status: \(subscriptionStatus), Count: \(promptCount)")
    }
    
    deinit {
        periodicCheckTimer?.invalidate()
    }
}

// MARK: - Serialization Helper (Simplified)

private struct SubscriptionStatusData: Codable {
    let type: String
    let expiresAt: Date?
    
    static func from(_ status: SubscriptionManager.SubscriptionStatus) -> SubscriptionStatusData {
        switch status {
        case .free:
            return SubscriptionStatusData(type: "free", expiresAt: nil)
        case .subscribed(let expiresAt):
            return SubscriptionStatusData(type: "subscribed", expiresAt: expiresAt)
        case .expired:
            return SubscriptionStatusData(type: "expired", expiresAt: nil)
        }
    }
    
    func toSubscriptionStatus() -> SubscriptionManager.SubscriptionStatus {
        switch type {
        case "free":
            return .free
        case "subscribed":
            return .subscribed(expiresAt: expiresAt)
        case "expired":
            return .expired
        // Handle legacy trialing status by converting to subscribed
        case "trialing":
            return .subscribed(expiresAt: expiresAt)
        default:
            return .free
        }
    }
}