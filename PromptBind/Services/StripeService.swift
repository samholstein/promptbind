import Foundation
import AppKit

@MainActor
class StripeService: ObservableObject {
    static let shared = StripeService()
    
    @Published var isLoading = false
    @Published var lastError: StripeError?
    
    // Direct Stripe integration configuration
    private let publishableKey = "pk_live_51RpyfmE3AkOk58OIAswQOdFZJrpkOOY7XEP6b7V4rFgL6jZXwi9a6vczf72nhZRZhQWvRnQ7PMKjGLlbVBc6CBlR00x76i7RWK"
    private let stripeAPIBaseURL = "https://api.stripe.com/v1"
    
    // Stripe Payment Link - secure and no backend required!
    private let paymentLinkURL = "https://buy.stripe.com/9B6cN5f6kePSc8r8es4gg00"
    
    private init() {}
    
    // MARK: - Direct Stripe Payment Link
    
    /// Opens the Stripe Payment Link in the default browser
    func openCheckout() {
        print("StripeService: Opening Stripe Payment Link...")
        
        guard let url = URL(string: paymentLinkURL) else {
            print("StripeService: Invalid payment link URL")
            lastError = StripeError.invalidURL
            return
        }
        
        NSWorkspace.shared.open(url)
        print("StripeService: Opened payment link in browser")
    }
    
    // MARK: - Stripe API Integration (for verification only)
    
    /// Retrieves a checkout session from Stripe API
    func getCheckoutSession(_ sessionId: String) async throws -> StripeCheckoutSession {
        print("StripeService: Retrieving checkout session: \(sessionId)")
        
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        
        let endpoint = "/checkout/sessions/\(sessionId)"
        let response: StripeCheckoutSession = try await makeStripeAPIRequest(
            endpoint: endpoint,
            method: "GET",
            body: nil as String?
        )
        
        print("StripeService: Retrieved checkout session with status: \(response.paymentStatus)")
        return response
    }
    
    /// Retrieves a subscription from Stripe API
    func getSubscription(_ subscriptionId: String) async throws -> StripeSubscription {
        print("StripeService: Retrieving subscription: \(subscriptionId)")
        
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        
        let endpoint = "/subscriptions/\(subscriptionId)"
        let response: StripeSubscription = try await makeStripeAPIRequest(
            endpoint: endpoint,
            method: "GET",
            body: nil as String?
        )
        
        print("StripeService: Retrieved subscription with status: \(response.status)")
        return response
    }
    
    /// Checks subscription status for a customer
    func getCustomerSubscriptions(_ customerId: String) async throws -> StripeSubscriptionList {
        print("StripeService: Retrieving subscriptions for customer: \(customerId)")
        
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        
        let endpoint = "/subscriptions?customer=\(customerId)&status=all&limit=10"
        let response: StripeSubscriptionList = try await makeStripeAPIRequest(
            endpoint: endpoint,
            method: "GET",
            body: nil as String?
        )
        
        print("StripeService: Retrieved \(response.data.count) subscriptions for customer")
        return response
    }
    
    // MARK: - Generic Stripe API Helper (Read-only operations)
    
    private func makeStripeAPIRequest<T: Codable, U: Codable>(
        endpoint: String,
        method: String,
        body: T?
    ) async throws -> U {
        guard let url = URL(string: stripeAPIBaseURL + endpoint) else {
            throw StripeError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // For read-only operations, we can use the publishable key
        // This is secure for client-side operations like retrieving checkout sessions
        let authData = (publishableKey + ":").data(using: .utf8)!
        let base64Auth = authData.base64EncodedString()
        request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
        
        if let body = body {
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw StripeError.encodingError(error)
            }
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw StripeError.invalidResponse
            }
            
            // Log the response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("StripeService: API Response (\(httpResponse.statusCode)): \(responseString.prefix(200))...")
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("StripeService: API Error (\(httpResponse.statusCode)): \(errorMessage)")
                throw StripeError.serverError(httpResponse.statusCode, errorMessage)
            }
            
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                let decodedResponse = try decoder.decode(U.self, from: data)
                return decodedResponse
            } catch {
                print("StripeService: Decoding error: \(error)")
                throw StripeError.decodingError(error)
            }
            
        } catch let error as StripeError {
            lastError = error
            throw error
        } catch {
            let stripeError = StripeError.networkError(error)
            lastError = stripeError
            throw stripeError
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Verifies a checkout session and returns subscription data
    func verifyCheckoutSession(_ sessionId: String) async throws -> SubscriptionData {
        print("StripeService: Verifying checkout session: \(sessionId)")
        
        let session = try await getCheckoutSession(sessionId)
        
        guard session.paymentStatus == "paid" || session.paymentStatus == "no_payment_required" else {
            print("StripeService: Checkout session not completed: \(session.paymentStatus)")
            throw StripeError.subscriptionNotFound
        }
        
        guard let subscriptionId = session.subscription else {
            print("StripeService: No subscription ID in checkout session")
            throw StripeError.subscriptionNotFound
        }
        
        let subscription = try await getSubscription(subscriptionId)
        
        return SubscriptionData(
            status: subscription.status,
            expiresAt: subscription.currentPeriodEnd,
            customerId: subscription.customer,
            subscriptionId: subscription.id
        )
    }
    
    /// Checks current subscription status for a device (using stored customer ID)
    func checkDeviceSubscriptionStatus() async throws -> SubscriptionData? {
        print("StripeService: Checking device subscription status...")
        
        // Get device subscription from Core Data
        guard let deviceSubscription = CoreDataStack.shared.getDeviceSubscription(),
              let customerId = deviceSubscription.subscriptionCustomerId else {
            print("StripeService: No customer ID found for device")
            return nil
        }
        
        let subscriptionList = try await getCustomerSubscriptions(customerId)
        
        // Find the most recent active subscription
        let activeSubscription = subscriptionList.data
            .filter { $0.status == "active" || $0.status == "trialing" }
            .sorted { $0.created > $1.created }
            .first
        
        if let subscription = activeSubscription {
            return SubscriptionData(
                status: subscription.status,
                expiresAt: subscription.currentPeriodEnd,
                customerId: subscription.customer,
                subscriptionId: subscription.id
            )
        } else {
            // No active subscription found
            return SubscriptionData(
                status: "inactive",
                expiresAt: nil,
                customerId: customerId,
                subscriptionId: nil
            )
        }
    }
}

// MARK: - Stripe API Data Models

struct StripeCheckoutSession: Codable {
    let id: String
    let paymentStatus: String
    let subscription: String?
    let customer: String?
    let clientReferenceId: String?
    
    private enum CodingKeys: String, CodingKey {
        case id
        case paymentStatus = "payment_status"
        case subscription
        case customer
        case clientReferenceId = "client_reference_id"
    }
}

struct StripeSubscription: Codable {
    let id: String
    let status: String
    let customer: String
    let currentPeriodEnd: Date
    let currentPeriodStart: Date
    let created: TimeInterval
    
    private enum CodingKeys: String, CodingKey {
        case id
        case status
        case customer
        case currentPeriodEnd = "current_period_end"
        case currentPeriodStart = "current_period_start"
        case created
    }
}

struct StripeSubscriptionList: Codable {
    let data: [StripeSubscription]
    let hasMore: Bool
    
    private enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
    }
}

// MARK: - Legacy Data Models (for compatibility)

struct SubscriptionData: Codable {
    let status: String // "active", "inactive", "expired", "trialing"
    let expiresAt: Date?
    let customerId: String?
    let subscriptionId: String?
}

// MARK: - Error Handling

enum StripeError: LocalizedError {
    case invalidURL
    case encodingError(Error)
    case decodingError(Error)
    case networkError(Error)
    case serverError(Int, String)
    case invalidResponse
    case subscriptionNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .encodingError(let error):
            return "Encoding error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .subscriptionNotFound:
            return "Subscription not found"
        }
    }
}