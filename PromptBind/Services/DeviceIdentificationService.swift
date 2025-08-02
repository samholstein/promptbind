import Foundation
import Security

class DeviceIdentificationService {
    static let shared = DeviceIdentificationService()
    
    private let service = "com.promptbind.device-id"
    private let account = "device-identifier"
    
    private init() {}
    
    /// Gets or creates a unique device identifier stored in Keychain
    func getDeviceID() -> String {
        // Try to retrieve existing device ID from Keychain
        if let existingID = getFromKeychain() {
            print("DeviceIdentificationService: Retrieved existing device ID: \(existingID.prefix(8))...")
            return existingID
        }
        
        // Create new device ID
        let newID = UUID().uuidString
        
        // Store in Keychain
        if saveToKeychain(newID) {
            print("DeviceIdentificationService: Created new device ID: \(newID.prefix(8))...")
            return newID
        } else {
            print("DeviceIdentificationService: Failed to save to Keychain, using session ID")
            // Fallback to memory-only ID (not ideal but better than failing)
            return newID
        }
    }
    
    private func getFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let deviceID = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return deviceID
    }
    
    private func saveToKeychain(_ deviceID: String) -> Bool {
        guard let data = deviceID.data(using: .utf8) else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        
        // Delete any existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// For testing purposes - clear the device ID
    func clearDeviceID() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        print("DeviceIdentificationService: Cleared device ID")
        return status == errSecSuccess || status == errSecItemNotFound
    }
}