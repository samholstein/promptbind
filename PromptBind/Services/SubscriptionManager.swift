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
    
    // MARK: - Private Properties
    private let maxFreePrompts = 5
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Subscription Status
    enum SubscriptionStatus: Equatable {
        case free
        case trialing(expiresAt: Date)
        case subscribed(expiresAt: Date?)
        case expired
        
        var isActive: Bool {
            switch self {
            case .free:
                return false
            case .trialing(let expiresAt):
                return expiresAt > Date()
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
            case .trialing:
                return "Trial"
            case .subscribed:
                return "Pro"
            case .expired:
                return "Expired"
            }
        }
    }
    
    private init() {
        loadSubscriptionState()
        print("SubscriptionManager: Initialized with status: \(subscriptionStatus), count: \(promptCount)")
        
        // Refresh prompt count from Core Data on startup
        refreshPromptCount()
    }
    
    // MARK: - Public Methods
    
    /// Force refresh the prompt count from Core Data
    func refreshPromptCount() {
        let count = CoreDataStack.shared.promptCount()
        updatePromptCount(count)
        print("SubscriptionManager: Refreshed prompt count: \(count)")
    }
    
    /// Updates the current prompt count
    func updatePromptCount(_ count: Int) {
        print("SubscriptionManager: Updating prompt count from \(promptCount) to \(count)")
        promptCount = count
        saveSubscriptionState() // Save the updated count
    }
    
    /// Checks if user can create a new prompt
    func canCreatePrompt() -> Bool {
        let result: Bool
        switch subscriptionStatus {
        case .free:
            result = promptCount < maxFreePrompts
            print("SubscriptionManager: Can create prompt (free): \(result) (\(promptCount)/\(maxFreePrompts))")
        case .trialing(let expiresAt):
            result = expiresAt > Date()
            print("SubscriptionManager: Can create prompt (trial): \(result)")
        case .subscribed:
            result = true
            print("SubscriptionManager: Can create prompt (subscribed): true")
        case .expired:
            result = false
            print("SubscriptionManager: Can create prompt (expired): false")
        }
        return result
    }
    
    /// Checks if user is at the free limit
    func isAtFreeLimit() -> Bool {
        guard case .free = subscriptionStatus else { return false }
        let atLimit = promptCount >= maxFreePrompts
        print("SubscriptionManager: Is at free limit: \(atLimit) (\(promptCount)/\(maxFreePrompts))")
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
    
    // MARK: - Subscription Management
    
    /// Activates a subscription (called after successful Stripe payment)
    func activateSubscription(expiresAt: Date? = nil) {
        print("SubscriptionManager: Activating subscription")
        subscriptionStatus = .subscribed(expiresAt: expiresAt)
        saveSubscriptionState()
    }
    
    /// Starts a trial period
    func startTrial(duration: TimeInterval = 30 * 24 * 60 * 60) { // 30 days default
        let expiresAt = Date().addingTimeInterval(duration)
        print("SubscriptionManager: Starting trial until \(expiresAt)")
        subscriptionStatus = .trialing(expiresAt: expiresAt)
        saveSubscriptionState()
    }
    
    /// Expires the current subscription
    func expireSubscription() {
        print("SubscriptionManager: Expiring subscription")
        subscriptionStatus = .expired
        saveSubscriptionState()
    }
    
    /// Resets to free tier (useful for testing)
    func resetToFree() {
        print("SubscriptionManager: Resetting to free tier")
        subscriptionStatus = .free
        saveSubscriptionState()
    }
    
    // MARK: - Persistence
    
    private func loadSubscriptionState() {
        let defaults = UserDefaults.standard
        
        // Load subscription status
        if let statusData = defaults.data(forKey: "subscriptionStatus"),
           let status = try? JSONDecoder().decode(SubscriptionStatusData.self, from: statusData) {
            subscriptionStatus = status.toSubscriptionStatus()
        }
        
        // Load prompt count (will be refreshed from Core Data)
        promptCount = defaults.integer(forKey: "promptCount")
        
        print("SubscriptionManager: Loaded state - Status: \(subscriptionStatus), Count: \(promptCount)")
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
        
        print("SubscriptionManager: Saved state - Status: \(subscriptionStatus), Count: \(promptCount)")
    }
}

// MARK: - Serialization Helper

private struct SubscriptionStatusData: Codable {
    let type: String
    let expiresAt: Date?
    
    static func from(_ status: SubscriptionManager.SubscriptionStatus) -> SubscriptionStatusData {
        switch status {
        case .free:
            return SubscriptionStatusData(type: "free", expiresAt: nil)
        case .trialing(let expiresAt):
            return SubscriptionStatusData(type: "trialing", expiresAt: expiresAt)
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
        case "trialing":
            return .trialing(expiresAt: expiresAt ?? Date())
        case "subscribed":
            return .subscribed(expiresAt: expiresAt)
        case "expired":
            return .expired
        default:
            return .free
        }
    }
}