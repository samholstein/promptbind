import Foundation
import CoreData
import CloudKit

class CoreDataStack: ObservableObject {
    static let shared = CoreDataStack()
    
    @Published var isCloudKitReady = false
    @Published var cloudKitError: String?
    
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
        promptExpansion.name = "expansion"
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
        let storeDescription = container.persistentStoreDescriptions.first!
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
            } catch {
                print("Core Data save error: \(error.localizedDescription)")
            }
        }
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
        checkCloudKitStatus()
    }
}