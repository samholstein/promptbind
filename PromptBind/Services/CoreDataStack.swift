import Foundation
import CoreData
import CloudKit
import Combine

class CoreDataStack: ObservableObject {
    static let shared = CoreDataStack()
    
    @Published var isCloudKitReady = false
    @Published var cloudKitError: String?
    
    // New properties for detailed sync status
    @Published var syncStatus: CloudKitSyncStatus = .notSyncing
    @Published var lastSyncDate: Date?
    @Published var lastSyncError: String?
    
    private var syncTimeoutTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    lazy var persistentContainer: NSPersistentContainer = {
        let model = NSManagedObjectModel()
        
        // Create Category entity
        let categoryEntity = NSEntityDescription()
        categoryEntity.name = "Category"
        categoryEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        
        let categoryId = NSAttributeDescription()
        categoryId.name = "id"
        categoryId.attributeType = .UUIDAttributeType
        categoryId.isOptional = true  // CloudKit requires optional or default value
        categoryId.defaultValue = UUID()  // Provide default value
        
        let categoryName = NSAttributeDescription()
        categoryName.name = "name"
        categoryName.attributeType = .stringAttributeType
        categoryName.isOptional = true  // CloudKit requires optional or default value
        categoryName.defaultValue = ""  // Provide default value
        
        let categoryOrder = NSAttributeDescription()
        categoryOrder.name = "order"
        categoryOrder.attributeType = .integer16AttributeType
        categoryOrder.isOptional = true  // CloudKit requires optional or default value
        categoryOrder.defaultValue = 0  // Already had default value
        
        categoryEntity.properties = [categoryId, categoryName, categoryOrder]
        
        // Create Prompt entity
        let promptEntity = NSEntityDescription()
        promptEntity.name = "Prompt"  
        promptEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        
        let promptId = NSAttributeDescription()
        promptId.name = "id"
        promptId.attributeType = .UUIDAttributeType
        promptId.isOptional = true  // CloudKit requires optional or default value
        promptId.defaultValue = UUID()  // Provide default value
        
        let promptTrigger = NSAttributeDescription()
        promptTrigger.name = "trigger"
        promptTrigger.attributeType = .stringAttributeType
        promptTrigger.isOptional = true  // CloudKit requires optional or default value
        promptTrigger.defaultValue = ""  // Provide default value
        
        let promptExpansion = NSAttributeDescription()
        promptExpansion.name = "prompt"  // Changed from "expansion" to "prompt"
        promptExpansion.attributeType = .stringAttributeType
        promptExpansion.isOptional = true  // CloudKit requires optional or default value
        promptExpansion.defaultValue = ""  // Provide default value
        
        let promptEnabled = NSAttributeDescription()
        promptEnabled.name = "enabled"
        promptEnabled.attributeType = .booleanAttributeType
        promptEnabled.isOptional = true  // CloudKit requires optional or default value
        promptEnabled.defaultValue = true  // Already had default value
        
        promptEntity.properties = [promptId, promptTrigger, promptExpansion, promptEnabled]
        
        // Create relationship between Category and Prompt
        let categoryPromptsRelationship = NSRelationshipDescription()
        categoryPromptsRelationship.name = "prompts"
        categoryPromptsRelationship.destinationEntity = promptEntity
        categoryPromptsRelationship.minCount = 0
        categoryPromptsRelationship.maxCount = 0 // 0 means "to many"
        categoryPromptsRelationship.deleteRule = .cascadeDeleteRule
        categoryPromptsRelationship.isOptional = true
        
        let promptCategoryRelationship = NSRelationshipDescription()
        promptCategoryRelationship.name = "category"
        promptCategoryRelationship.destinationEntity = categoryEntity
        promptCategoryRelationship.minCount = 0
        promptCategoryRelationship.maxCount = 1 // "to one"
        promptCategoryRelationship.deleteRule = .nullifyDeleteRule
        promptCategoryRelationship.isOptional = true
        
        // Set inverse relationships
        categoryPromptsRelationship.inverseRelationship = promptCategoryRelationship
        promptCategoryRelationship.inverseRelationship = categoryPromptsRelationship
        
        // Add relationships to entities
        categoryEntity.properties.append(categoryPromptsRelationship)
        promptEntity.properties.append(promptCategoryRelationship)
        
        // Add entities to model
        model.entities = [categoryEntity, promptEntity]
        
        // Create container with our model
        let container = NSPersistentCloudKitContainer(name: "PromptBind", managedObjectModel: model)
        
        // Configure for CloudKit
        guard let storeDescription = container.persistentStoreDescriptions.first else {
            fatalError("Failed to get persistent store description")
        }
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        // Set CloudKit container identifier
        storeDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.samholstein.PromptBind"
        )
        
        print("CoreDataStack: About to load persistent stores...")
        
        container.loadPersistentStores { [weak self] storeDescription, error in
            if let error = error {
                print("Core Data failed to load: \(error)")
                print("Core Data error details: \(error.localizedDescription)")
                if let nsError = error as NSError? {
                    print("Core Data error domain: \(nsError.domain)")
                    print("Core Data error code: \(nsError.code)")
                    print("Core Data error userInfo: \(nsError.userInfo)")
                }
                self?.cloudKitError = "Core Data initialization failed: \(error.localizedDescription)"
                self?.isCloudKitReady = false
            } else {
                print("Core Data loaded successfully!")
                self?.isCloudKitReady = true
                self?.cloudKitError = nil
                
                // Enable automatic merging
                container.viewContext.automaticallyMergesChangesFromParent = true
                container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                
                print("Core Data setup complete")
                
                // Start monitoring CloudKit events
                self?.monitorCloudKitEvents()
                
                // Update prompt count for subscription manager
                self?.updatePromptCount()
            }
        }
        
        return container
    }()
    
    var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    func save() {
        let context = persistentContainer.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
                print("Core Data saved successfully")
                
                // Update prompt count after saving
                updatePromptCount()
            } catch {
                print("Core Data save error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Subscription Support Methods
    
    /// Gets the current prompt count
    func promptCount() -> Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
        do {
            let count = try viewContext.count(for: request)
            print("CoreDataStack: Current prompt count: \(count)")
            return count
        } catch {
            print("CoreDataStack: Error counting prompts: \(error)")
            return 0
        }
    }
    
    /// Updates the subscription manager with current prompt count
    private func updatePromptCount() {
        Task { @MainActor in
            let count = promptCount()
            SubscriptionManager.shared.updatePromptCount(count)
        }
    }
    
    // Function to manually trigger a sync, if needed.
    func triggerCloudKitSync() {
        // This is a bit of a hack, as there's no direct "sync now" button.
        // We can request a refresh of the schema to encourage a sync.
        print("CoreDataStack: Manually triggering sync...")
        syncTimeoutTimer?.invalidate() // Invalidate any existing timer.
        
        self.syncStatus = .syncing
        self.lastSyncError = nil
        
        // Poke the container to encourage a sync.
        let container = self.persistentContainer as! NSPersistentCloudKitContainer
        do {
            try container.initializeCloudKitSchema()
        } catch {
            print("CoreDataStack: Error trying to poke container for sync: \(error)")
            // Don't treat this as a sync error, just log it.
        }
        
        // Set a timeout to revert the syncing status if no event is received.
        syncTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            if self.syncStatus == .syncing {
                print("CoreDataStack: Sync timeout reached. No event received, resetting status.")
                self.syncStatus = .synced // Assume it's fine if we didn't get an error.
            }
        }
    }
    
    private func monitorCloudKitEvents() {
        print("CoreDataStack: Subscribing to CloudKit event notifications...")
        NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self,
                      let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
                    return
                }
                
                print("CoreDataStack: Received CloudKit event: \(event.type)")
                
                switch event.type {
                case .setup:
                    print("CoreDataStack: Setup event finished.")
                    self.syncStatus = .notSyncing
                    self.syncTimeoutTimer?.invalidate()
                case .import:
                    if event.endDate != nil {
                        print("CoreDataStack: Import finished.")
                        self.syncTimeoutTimer?.invalidate() // A sync completed, cancel the timeout.
                        self.lastSyncDate = Date()
                        self.syncStatus = .synced
                        if let error = event.error {
                            self.lastSyncError = error.localizedDescription
                            self.syncStatus = .error
                            print("CoreDataStack: Import error: \(error.localizedDescription)")
                        } else {
                            self.lastSyncError = nil
                        }
                        
                        // Update prompt count after import
                        self.updatePromptCount()
                    } else {
                        print("CoreDataStack: Import started...")
                        self.syncStatus = .syncing
                    }
                case .export:
                    if event.endDate != nil {
                        print("CoreDataStack: Export finished.")
                        self.syncTimeoutTimer?.invalidate() // A sync completed, cancel the timeout.
                        self.lastSyncDate = Date()
                        self.syncStatus = .synced
                        if let error = event.error {
                            self.lastSyncError = error.localizedDescription
                            self.syncStatus = .error
                            print("CoreDataStack: Export error: \(error.localizedDescription)")
                        } else {
                            self.lastSyncError = nil
                        }
                    } else {
                        print("CoreDataStack: Export started...")
                        self.syncStatus = .syncing
                    }
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    func checkCloudKitStatus() {
        CKContainer(identifier: "iCloud.samholstein.PromptBind").accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    print("CloudKit account available")
                case .noAccount:
                    self?.cloudKitError = "Not signed into iCloud"
                    print("CloudKit: No iCloud account")
                case .restricted:
                    self?.cloudKitError = "iCloud account restricted"
                    print("CloudKit: Account restricted")
                case .couldNotDetermine:
                    self?.cloudKitError = "Could not determine iCloud status"
                    print("CloudKit: Could not determine status")
                case .temporarilyUnavailable:
                    self?.cloudKitError = "iCloud temporarily unavailable"
                    print("CloudKit: Temporarily unavailable")
                @unknown default:
                    self?.cloudKitError = "Unknown iCloud status"
                    print("CloudKit: Unknown status")
                }
            }
        }
    }
    
    private init() {
        // We call checkCloudKitStatus from the persistentContainer setup now
    }
}

// Enum to represent the detailed sync status
enum CloudKitSyncStatus: String {
    case notSyncing = "Not Syncing"
    case syncing = "Syncing..."
    case synced = "Up to Date"
    case error = "Sync Error"
}