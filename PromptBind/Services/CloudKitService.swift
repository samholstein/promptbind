import Foundation
import CloudKit
import CoreData

@MainActor
class CloudKitService: ObservableObject {
    @Published var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published var isSignedIn: Bool = false
    @Published var errorMessage: String?
    @Published var isSyncing: Bool = false
    
    private var container: CKContainer?
    
    init() {
        print("CloudKitService: Initializing...")
        setupCloudKit()
    }
    
    private func setupCloudKit() {
        print("CloudKitService: Setting up CloudKit...")
        
        // Use our configured container
        container = CKContainer(identifier: "iCloud.samholstein.PromptBind")
        checkAccountStatus()
    }
    
    func checkAccountStatus() {
        guard let container = container else {
            print("CloudKitService: No CloudKit container available")
            accountStatus = .noAccount
            isSignedIn = false
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
    
    func hasAddedDefaultPrompts(context: NSManagedObjectContext) async -> Bool {
        print("CloudKitService: Checking if default prompts have been added...")
        
        // Check if we have any prompts in Core Data
        let request = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
        do {
            let count = try context.count(for: request)
            print("CloudKitService: Found \(count) existing prompts")
            return count > 0
        } catch {
            print("CloudKitService: Error checking prompt count: \(error)")
            return false
        }
    }
    
    func markDefaultPromptsAsAdded() async {
        print("CloudKitService: Default prompts marked as added (handled by Core Data)")
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