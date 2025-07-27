import Foundation
import CloudKit
import SwiftData

@MainActor
class CloudKitService: ObservableObject {
    @Published var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published var isSignedIn: Bool = false
    @Published var errorMessage: String?
    @Published var isSyncing: Bool = false
    
    private let container = CKContainer(identifier: "iCloud.com.samholstein.PromptBind")
    private let recordZone = CKRecordZone(zoneName: "PromptBindZone")
    
    init() {
        checkAccountStatus()
        setupCustomZone()
    }
    
    func checkAccountStatus() {
        container.accountStatus { [weak self] status, error in
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
    
    private func setupCustomZone() {
        guard isSignedIn else { return }
        
        Task {
            do {
                let _ = try await container.privateCloudDatabase.save(recordZone)
                print("Custom zone created/verified")
            } catch {
                print("Error setting up custom zone: \(error)")
            }
        }
    }
    
    func hasAddedDefaultPrompts() async -> Bool {
        guard isSignedIn else { return false }
        
        do {
            let recordID = CKRecord.ID(recordName: "DefaultPromptsAdded", zoneID: recordZone.zoneID)
            let _ = try await container.privateCloudDatabase.record(for: recordID)
            return true
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                // Record doesn't exist, so defaults haven't been added
                return false
            }
            print("Error checking default prompts flag: \(error)")
            return false
        }
    }
    
    func markDefaultPromptsAsAdded() async {
        guard isSignedIn else { return }
        
        do {
            let recordID = CKRecord.ID(recordName: "DefaultPromptsAdded", zoneID: recordZone.zoneID)
            let record = CKRecord(recordType: "DefaultPromptsFlag", recordID: recordID)
            record["addedDate"] = Date()
            
            let _ = try await container.privateCloudDatabase.save(record)
            print("Successfully marked default prompts as added in CloudKit")
        } catch {
            print("Error marking default prompts as added: \(error)")
        }
    }
    
    // MARK: - Sync Methods
    
    func syncPromptsToCloud(_ prompts: [Prompt]) async {
        guard isSignedIn else { return }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            var recordsToSave: [CKRecord] = []
            
            for prompt in prompts {
                let recordID = CKRecord.ID(recordName: "prompt-\(prompt.id)", zoneID: recordZone.zoneID)
                let record = CKRecord(recordType: "Prompt", recordID: recordID)
                
                record["trigger"] = prompt.trigger
                record["expansion"] = prompt.expansion
                record["enabled"] = prompt.enabled
                record["categoryName"] = prompt.category?.name
                record["modifiedDate"] = Date()
                
                recordsToSave.append(record)
            }
            
            // Save records using modifyRecords
            let (savedRecords, _) = try await container.privateCloudDatabase.modifyRecords(
                saving: recordsToSave,
                deleting: []
            )
            
            print("Successfully synced \(savedRecords.count) prompts to CloudKit")
        } catch {
            print("Error syncing prompts to CloudKit: \(error)")
            errorMessage = "Sync failed: \(error.localizedDescription)"
        }
    }
    
    func syncPromptsFromCloud() async -> [CloudKitPrompt] {
        guard isSignedIn else { return [] }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            let query = CKQuery(recordType: "Prompt", predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "modifiedDate", ascending: false)]
            
            let (records, _) = try await container.privateCloudDatabase.records(matching: query, inZoneWith: recordZone.zoneID)
            
            var cloudPrompts: [CloudKitPrompt] = []
            for (_, result) in records {
                switch result {
                case .success(let record):
                    if let cloudPrompt = CloudKitPrompt(from: record) {
                        cloudPrompts.append(cloudPrompt)
                    }
                case .failure(let error):
                    print("Error fetching record: \(error)")
                }
            }
            
            print("Successfully fetched \(cloudPrompts.count) prompts from CloudKit")
            return cloudPrompts
        } catch {
            print("Error syncing prompts from CloudKit: \(error)")
            errorMessage = "Sync failed: \(error.localizedDescription)"
            return []
        }
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