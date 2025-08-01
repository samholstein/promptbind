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