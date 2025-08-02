import Foundation
import AppKit

@MainActor
class StripeService: ObservableObject {
    static let shared = StripeService()
    
    @Published var isLoading = false
    @Published var lastError: StripeError?
    
    // Production configuration - will be moved to environment variables
    private let productId = "prod_SnEGPJT55RGtL5" // Your actual Stripe product ID
    private let publishableKey = "pk_test_..." // TODO: Set your publishable key
    private let backendURL = "https://promptbind-backend.vercel.app" // TODO: Set your backend URL
    
    private init() {}
    
    // MARK: - Subscription Flow
    
    /// Creates a Stripe Checkout session for subscription
    func createCheckoutSession() async throws -> CheckoutSessionResponse {
        isLoading = true
        lastError = nil
        
        defer { isLoading = false }
        
        print("StripeService: Creating checkout session...")
        
        let deviceID = DeviceIdentificationService.shared.getDeviceID()
        
        let requestBody = CheckoutSessionRequest(
            deviceId: deviceID,
            productId: productId,
            successUrl: "promptbind://subscription/success",
            cancelUrl: "promptbind://subscription/cancel"
        )
        
        let response = try await makeRequest(
            endpoint: "/api/create-checkout-session",
            method: "POST",
            body: requestBody,
            responseType: CheckoutSessionResponse.self
        )
        
        print("StripeService: Checkout session created: \(response.sessionId)")
        return response
    }
    
    /// Verifies a completed subscription
    func verifySubscription(sessionId: String) async throws -> SubscriptionData {
        isLoading = true
        lastError = nil
        
        defer { isLoading = false }
        
        print("StripeService: Verifying subscription for session: \(sessionId)")
        
        let deviceID = DeviceIdentificationService.shared.getDeviceID()
        
        let requestBody = VerifySubscriptionRequest(
            sessionId: sessionId,
            deviceId: deviceID
        )
        
        let response = try await makeRequest(
            endpoint: "/api/verify-subscription",
            method: "POST",
            body: requestBody,
            responseType: SubscriptionData.self
        )
        
        print("StripeService: Subscription verified: \(response.status)")
        return response
    }
    
    /// Checks current subscription status
    func checkSubscriptionStatus() async throws -> SubscriptionData {
        isLoading = true
        lastError = nil
        
        defer { isLoading = false }
        
        print("StripeService: Checking subscription status...")
        
        let deviceID = DeviceIdentificationService.shared.getDeviceID()
        
        let response = try await makeRequest(
            endpoint: "/api/subscription-status/\(deviceID)",
            method: "GET",
            body: nil as String?,
            responseType: SubscriptionData.self
        )
        
        print("StripeService: Subscription status: \(response.status)")
        return response
    }
    
    /// Opens Stripe Checkout in the default browser
    func openCheckoutUrl(_ url: String) {
        guard let checkoutUrl = URL(string: url) else {
            print("StripeService: Invalid checkout URL: \(url)")
            return
        }
        
        print("StripeService: Opening checkout URL in browser")
        NSWorkspace.shared.open(checkoutUrl)
    }
    
    // MARK: - Generic HTTP Helper
    
    private func makeRequest<T: Codable, U: Codable>(
        endpoint: String,
        method: String,
        body: T?,
        responseType: U.Type
    ) async throws -> U {
        guard let url = URL(string: backendURL + endpoint) else {
            throw StripeError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
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
            
            guard 200...299 ~= httpResponse.statusCode else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw StripeError.serverError(httpResponse.statusCode, errorMessage)
            }
            
            do {
                let decodedResponse = try JSONDecoder().decode(responseType, from: data)
                return decodedResponse
            } catch {
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
}

// MARK: - Data Models

struct CheckoutSessionRequest: Codable {
    let deviceId: String
    let productId: String // Changed from priceId to productId
    let successUrl: String
    let cancelUrl: String
}

struct CheckoutSessionResponse: Codable {
    let sessionId: String
    let checkoutUrl: String
}

struct VerifySubscriptionRequest: Codable {
    let sessionId: String
    let deviceId: String
}

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