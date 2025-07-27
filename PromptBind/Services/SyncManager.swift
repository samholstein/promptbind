import Foundation
import SwiftData

@MainActor
class SyncManager: ObservableObject {
    private let cloudKitService: CloudKitService
    private let modelContext: ModelContext
    
    @Published var lastSyncDate: Date?
    @Published var syncStatus: SyncStatus = .idle
    
    enum SyncStatus: Equatable {
        case idle
        case syncing
        case success
        case error(String)
        
        static func == (lhs: SyncStatus, rhs: SyncStatus) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.syncing, .syncing), (.success, .success):
                return true
            case (.error(let lhsMessage), .error(let rhsMessage)):
                return lhsMessage == rhsMessage
            default:
                return false
            }
        }
    }
    
    init(cloudKitService: CloudKitService, modelContext: ModelContext) {
        self.cloudKitService = cloudKitService
        self.modelContext = modelContext
        self.lastSyncDate = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date
    }
    
    func performSync() async {
        guard cloudKitService.isSignedIn else {
            syncStatus = .error("Not signed into iCloud")
            return
        }
        
        syncStatus = .syncing
        
        do {
            // 1. Get local prompts
            let descriptor = FetchDescriptor<Prompt>()
            let localPrompts = try modelContext.fetch(descriptor)
            
            // 2. Upload local prompts to CloudKit
            await cloudKitService.syncPromptsToCloud(localPrompts)
            
            // 3. Download prompts from CloudKit
            let cloudPrompts = await cloudKitService.syncPromptsFromCloud()
            
            // 4. Merge changes (simple strategy: CloudKit wins for now)
            await mergeCloudPrompts(cloudPrompts)
            
            // 5. Update sync status
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: "lastSyncDate")
            syncStatus = .success
            
            print("Sync completed successfully")
        } catch {
            syncStatus = .error(error.localizedDescription)
            print("Sync failed: \(error)")
        }
    }
    
    private func mergeCloudPrompts(_ cloudPrompts: [CloudKitPrompt]) async {
        // Simple merge strategy: Add any prompts that don't exist locally
        // In a more sophisticated version, we'd compare modification dates
        
        do {
            let descriptor = FetchDescriptor<Prompt>()
            let localPrompts = try modelContext.fetch(descriptor)
            let localTriggers = Set(localPrompts.map { $0.trigger })
            
            // Get categories map
            let categoryDescriptor = FetchDescriptor<Category>()
            let categories = try modelContext.fetch(categoryDescriptor)
            let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.name, $0) })
            
            var addedCount = 0
            for cloudPrompt in cloudPrompts {
                if !localTriggers.contains(cloudPrompt.trigger) {
                    let newPrompt = Prompt(
                        trigger: cloudPrompt.trigger,
                        expansion: cloudPrompt.expansion,
                        enabled: cloudPrompt.enabled
                    )
                    
                    // Assign category if it exists
                    if let categoryName = cloudPrompt.categoryName,
                       let category = categoryMap[categoryName] {
                        newPrompt.category = category
                    }
                    
                    modelContext.insert(newPrompt)
                    addedCount += 1
                }
            }
            
            if addedCount > 0 {
                try modelContext.save()
                print("Added \(addedCount) prompts from CloudKit")
            }
        } catch {
            print("Error merging cloud prompts: \(error)")
        }
    }
}