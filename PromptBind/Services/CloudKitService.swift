import Foundation
import CloudKit
import SwiftData

@MainActor
class CloudKitService: ObservableObject {
    @Published var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published var isSignedIn: Bool = false
    @Published var errorMessage: String?
    @Published var isSyncing: Bool = false
    
    private var container: CKContainer?
    private let recordZone = CKRecordZone(zoneName: "PromptBindZone")
    
    init() {
        print("CloudKitService: Initializing...")
        setupCloudKit()
    }
    
    private func setupCloudKit() {
        // For now, disable CloudKit until container is properly configured
        print("CloudKitService: CloudKit disabled - using local storage only")
        accountStatus = .noAccount
        isSignedIn = false
        
        // Uncomment this when CloudKit container is ready:
        /*
        do {
            container = CKContainer(identifier: "iCloud.com.samholstein.PromptBind")
            checkAccountStatus()
        } catch {
            print("CloudKitService: Failed to initialize CloudKit container: \(error)")
            accountStatus = .noAccount
            isSignedIn = false
        }
        */
    }
    
    func checkAccountStatus() {
        guard let container = container else {
            print("CloudKitService: No CloudKit container available")
            return
        }
        
        print("CloudKitService: Checking account status...")
        
        container.accountStatus { [weak self] status, error in
            print("CloudKitService: Account status callback - status: \(status), error: \(String(describing: error))")
            
            DispatchQueue.main.async {
                self?.accountStatus = status
                self?.isSignedIn = status == .available
                
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    print("CloudKit account status error: \(error)")
                } else {
                    self?.errorMessage = nil
                    print("CloudKit account status: \(status.description)")
                }
            }
        }
    }
    
    func hasAddedDefaultPrompts() async -> Bool {
        print("CloudKitService: CloudKit disabled - returning false for default prompts")
        return false
    }
    
    func markDefaultPromptsAsAdded() async {
        print("CloudKitService: CloudKit disabled - cannot mark default prompts as added")
    }
    
    // MARK: - Sync Methods (disabled for now)
    
    func syncPromptsToCloud(_ prompts: [Prompt]) async {
        print("CloudKitService: CloudKit disabled - sync to cloud not available")
    }
    
    func syncPromptsFromCloud() async -> [CloudKitPrompt] {
        print("CloudKitService: CloudKit disabled - sync from cloud not available")
        return []
    }
}

// MARK: - CloudKit Data Models

struct CloudKitPrompt {
    let id: String
    let trigger: String
    let expansion: String
    let enabled: Bool
    let categoryName: String?
    let modifiedDate: Date
    
    init?(from record: CKRecord) {
        guard let trigger = record["trigger"] as? String,
              let expansion = record["expansion"] as? String,
              let enabled = record["enabled"] as? Bool else {
            return nil
        }
        
        self.id = record.recordID.recordName
        self.trigger = trigger
        self.expansion = expansion
        self.enabled = enabled
        self.categoryName = record["categoryName"] as? String
        self.modifiedDate = record["modifiedDate"] as? Date ?? Date()
    }
}

extension CKAccountStatus {
    var description: String {
        switch self {
        case .couldNotDetermine:
            return "Could not determine"
        case .available:
            return "Available"
        case .restricted:
            return "Restricted"
        case .noAccount:
            return "No account"
        case .temporarilyUnavailable:
            return "Temporarily unavailable"
        @unknown default:
            return "Unknown"
        }
    }
}