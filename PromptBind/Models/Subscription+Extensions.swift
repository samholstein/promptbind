import Foundation
import CoreData

extension NSManagedObject {
    // Subscription-specific extensions for NSManagedObject
    var subscriptionID: UUID {
        get { value(forKey: "id") as? UUID ?? UUID() }
        set { setValue(newValue, forKey: "id") }
    }
    
    var subscriptionDeviceId: String {
        get { value(forKey: "deviceId") as? String ?? "" }
        set { setValue(newValue, forKey: "deviceId") }
    }
    
    var subscriptionStatus: String {
        get { value(forKey: "status") as? String ?? "free" }
        set { setValue(newValue, forKey: "status") }
    }
    
    var subscriptionCustomerId: String? {
        get { value(forKey: "customerId") as? String }
        set { setValue(newValue, forKey: "customerId") }
    }
    
    var subscriptionStripeSubscriptionId: String? {
        get { value(forKey: "stripeSubscriptionId") as? String }
        set { setValue(newValue, forKey: "stripeSubscriptionId") }
    }
    
    var subscriptionExpiresAt: Date? {
        get { value(forKey: "expiresAt") as? Date }
        set { setValue(newValue, forKey: "expiresAt") }
    }
    
    var subscriptionLastChecked: Date {
        get { value(forKey: "lastChecked") as? Date ?? Date() }
        set { setValue(newValue, forKey: "lastChecked") }
    }
    
    var subscriptionCreatedAt: Date {
        get { value(forKey: "createdAt") as? Date ?? Date() }
        set { setValue(newValue, forKey: "createdAt") }
    }
    
    var subscriptionUpdatedAt: Date {
        get { value(forKey: "updatedAt") as? Date ?? Date() }
        set { setValue(newValue, forKey: "updatedAt") }
    }
    
    // Helper methods for Subscription
    var isSubscription: Bool {
        return entity.name == "Subscription"
    }
    
    var isActiveSubscription: Bool {
        guard isSubscription else { return false }
        
        let status = subscriptionStatus.lowercased()
        
        // Both "active" and "trialing" are considered active (Pro access)
        // Stripe manages the trial logic internally
        switch status {
        case "active", "trialing":
            return true
        case "canceled", "cancelled", "past_due", "unpaid", "incomplete", "incomplete_expired":
            return false
        default:
            return false
        }
    }
    
    var subscriptionDisplayStatus: String {
        guard isSubscription else { return "Unknown" }
        
        switch subscriptionStatus.lowercased() {
        case "active":
            return "Pro"
        case "trialing":
            return "Pro (Trial)" // Simplified - Stripe manages trial details
        case "canceled", "cancelled":
            return "Cancelled"
        case "past_due":
            return "Past Due"
        case "unpaid":
            return "Unpaid"
        case "incomplete":
            return "Incomplete"
        case "incomplete_expired":
            return "Expired"
        default:
            return "Free"
        }
    }
    
    /// Checks if this subscription needs a status update (older than 24 hours)
    var needsStatusUpdate: Bool {
        guard isSubscription else { return false }
        
        let lastChecked = subscriptionLastChecked
        let dayInterval: TimeInterval = 24 * 60 * 60 // 24 hours
        
        return Date().timeIntervalSince(lastChecked) > dayInterval
    }
}

// Convenience methods for creating subscriptions
extension NSManagedObjectContext {
    func createSubscription(
        deviceId: String,
        status: String = "free",
        customerId: String? = nil,
        stripeSubscriptionId: String? = nil,
        expiresAt: Date? = nil
    ) -> NSManagedObject {
        let subscription = NSEntityDescription.insertNewObject(forEntityName: "Subscription", into: self)
        subscription.subscriptionID = UUID()
        subscription.subscriptionDeviceId = deviceId
        subscription.subscriptionStatus = status
        subscription.subscriptionCustomerId = customerId
        subscription.subscriptionStripeSubscriptionId = stripeSubscriptionId
        subscription.subscriptionExpiresAt = expiresAt
        subscription.subscriptionLastChecked = Date()
        subscription.subscriptionCreatedAt = Date()
        subscription.subscriptionUpdatedAt = Date()
        return subscription
    }
}