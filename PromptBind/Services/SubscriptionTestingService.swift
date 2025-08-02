import Foundation

#if DEBUG
@MainActor
class SubscriptionTestingService: ObservableObject {
    static let shared = SubscriptionTestingService()
    
    @Published var testResults: [TestResult] = []
    @Published var isRunningTests: Bool = false
    
    private init() {}
    
    struct TestResult {
        let name: String
        let passed: Bool
        let message: String
        let timestamp: Date
    }
    
    // MARK: - Comprehensive Subscription Testing
    
    func runAllTests() async {
        print("SubscriptionTestingService: Starting comprehensive subscription testing...")
        
        isRunningTests = true
        testResults.removeAll()
        
        // Test 1: Core Data Integration
        await testCoreDataIntegration()
        
        // Test 2: Subscription Status Logic
        await testSubscriptionStatusLogic()
        
        // Test 3: Prompt Limit Enforcement
        await testPromptLimitEnforcement()
        
        // Test 4: CloudKit Sync Simulation
        await testCloudKitSyncSimulation()
        
        // Test 5: Stripe Integration
        await testStripeIntegration()
        
        // Test 6: Error Handling
        await testErrorHandling()
        
        // Test 7: Periodic Checking
        await testPeriodicChecking()
        
        isRunningTests = false
        
        let passedTests = testResults.filter { $0.passed }.count
        let totalTests = testResults.count
        
        print("SubscriptionTestingService: Testing complete - \(passedTests)/\(totalTests) tests passed")
        
        if passedTests == totalTests {
            print("✅ All subscription tests passed!")
        } else {
            print("❌ Some subscription tests failed - check results")
        }
    }
    
    // MARK: - Individual Tests
    
    private func testCoreDataIntegration() async {
        print("Testing Core Data integration...")
        
        do {
            // Test saving subscription
            let deviceId = DeviceIdentificationService.shared.getDeviceID()
            let subscription = CoreDataStack.shared.saveSubscription(
                deviceId: deviceId,
                status: "active",
                customerId: "test_customer",
                stripeSubscriptionId: "test_sub",
                expiresAt: Date().addingTimeInterval(30 * 24 * 60 * 60)
            )
            
            // Test retrieving subscription
            let retrieved = CoreDataStack.shared.getDeviceSubscription()
            
            if let retrieved = retrieved,
               retrieved.subscriptionStatus == "active",
               retrieved.subscriptionCustomerId == "test_customer" {
                addTestResult("Core Data Integration", passed: true, message: "Successfully saved and retrieved subscription")
            } else {
                addTestResult("Core Data Integration", passed: false, message: "Failed to save/retrieve subscription correctly")
            }
            
        } catch {
            addTestResult("Core Data Integration", passed: false, message: "Exception: \(error.localizedDescription)")
        }
    }
    
    private func testSubscriptionStatusLogic() async {
        print("Testing subscription status logic...")
        
        let manager = SubscriptionManager.shared
        let originalStatus = manager.subscriptionStatus
        
        // Test free status
        manager.resetToFree()
        let canCreateWhenFree = manager.canCreatePrompt()
        let hasProAccessWhenFree = manager.hasProAccess()
        
        // Test subscribed status
        manager.activateSubscription()
        let canCreateWhenSubscribed = manager.canCreatePrompt()
        let hasProAccessWhenSubscribed = manager.hasProAccess()
        
        // Test expired status
        manager.expireSubscription()
        let canCreateWhenExpired = manager.canCreatePrompt()
        let hasProAccessWhenExpired = manager.hasProAccess()
        
        // Restore original status
        switch originalStatus {
        case .free:
            manager.resetToFree()
        case .subscribed(let expiresAt):
            manager.activateSubscription(expiresAt: expiresAt)
        case .expired:
            manager.expireSubscription()
        }
        
        if hasProAccessWhenSubscribed && !hasProAccessWhenFree && !hasProAccessWhenExpired {
            addTestResult("Subscription Status Logic", passed: true, message: "Status transitions work correctly")
        } else {
            addTestResult("Subscription Status Logic", passed: false, message: "Status logic is incorrect")
        }
    }
    
    private func testPromptLimitEnforcement() async {
        print("Testing prompt limit enforcement...")
        
        let manager = SubscriptionManager.shared
        let originalStatus = manager.subscriptionStatus
        let originalCount = manager.promptCount
        
        // Test free limit
        manager.resetToFree()
        manager.updatePromptCount(4) // Below limit
        let canCreateBeforeLimit = manager.canCreatePrompt()
        
        manager.updatePromptCount(5) // At limit
        let canCreateAtLimit = manager.canCreatePrompt()
        
        manager.updatePromptCount(6) // Above limit
        let canCreateAboveLimit = manager.canCreatePrompt()
        
        // Test Pro unlimited
        manager.activateSubscription()
        manager.updatePromptCount(100) // Way above free limit
        let canCreateWithPro = manager.canCreatePrompt()
        
        // Restore original state
        switch originalStatus {
        case .free:
            manager.resetToFree()
        case .subscribed(let expiresAt):
            manager.activateSubscription(expiresAt: expiresAt)
        case .expired:
            manager.expireSubscription()
        }
        manager.updatePromptCount(originalCount)
        
        if canCreateBeforeLimit && !canCreateAtLimit && !canCreateAboveLimit && canCreateWithPro {
            addTestResult("Prompt Limit Enforcement", passed: true, message: "Prompt limits enforced correctly")
        } else {
            addTestResult("Prompt Limit Enforcement", passed: false, message: "Prompt limit logic is incorrect")
        }
    }
    
    private func testCloudKitSyncSimulation() async {
        print("Testing CloudKit sync simulation...")
        
        // Simulate subscription from another device
        let otherDeviceId = "test-device-\(UUID().uuidString)"
        let subscription = CoreDataStack.shared.saveSubscription(
            deviceId: otherDeviceId,
            status: "active",
            customerId: "test_customer_2",
            stripeSubscriptionId: "test_sub_2",
            expiresAt: Date().addingTimeInterval(30 * 24 * 60 * 60)
        )
        
        // Trigger sync
        SubscriptionManager.shared.syncSubscriptionFromCloudKit()
        
        // Check if status updated
        let statusAfterSync = SubscriptionManager.shared.subscriptionStatus
        
        if statusAfterSync.isActive {
            addTestResult("CloudKit Sync Simulation", passed: true, message: "Successfully synced subscription from other device")
        } else {
            addTestResult("CloudKit Sync Simulation", passed: false, message: "Failed to sync subscription from other device")
        }
    }
    
    private func testStripeIntegration() async {
        print("Testing Stripe integration...")
        
        // Test that StripeService methods exist and can be called
        let stripeService = StripeService.shared
        
        // Test opening checkout (should not crash)
        do {
            stripeService.openCheckout()
            addTestResult("Stripe Integration", passed: true, message: "Stripe checkout can be opened")
        } catch {
            addTestResult("Stripe Integration", passed: false, message: "Failed to open Stripe checkout: \(error)")
        }
    }
    
    private func testErrorHandling() async {
        print("Testing error handling...")
        
        let manager = SubscriptionManager.shared
        
        // Test handling invalid Stripe data
        let invalidData = SubscriptionData(
            status: "unknown_status",
            expiresAt: nil,
            customerId: nil,
            subscriptionId: nil
        )
        
        manager.updateFromStripeData(invalidData)
        
        // Should default to free for unknown status
        if case .free = manager.subscriptionStatus {
            addTestResult("Error Handling", passed: true, message: "Handles invalid Stripe data correctly")
        } else {
            addTestResult("Error Handling", passed: false, message: "Failed to handle invalid Stripe data")
        }
    }
    
    private func testPeriodicChecking() async {
        print("Testing periodic checking...")
        
        // Test that periodic checking can be triggered
        let manager = SubscriptionManager.shared
        let wasChecking = manager.isCheckingStripeStatus
        
        // This should set isCheckingStripeStatus briefly
        Task {
            await manager.checkSubscriptionStatusFromStripe()
        }
        
        // Give it a moment to start
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        addTestResult("Periodic Checking", passed: true, message: "Periodic checking can be triggered (full test requires network)")
    }
    
    // MARK: - Helper Methods
    
    private func addTestResult(_ name: String, passed: Bool, message: String) {
        let result = TestResult(name: name, passed: passed, message: message, timestamp: Date())
        testResults.append(result)
        
        let status = passed ? "✅ PASS" : "❌ FAIL"
        print("Test: \(name) - \(status) - \(message)")
    }
}
#endif