import Foundation
import CoreData
import CloudKit

class CoreDataStack: ObservableObject {
    static let shared = CoreDataStack()
    
    @Published var isCloudKitReady = false
    @Published var cloudKitError: String?
    
    lazy var persistentContainer: NSPersistentContainer = {
        // Create the model programmatically
        let model = createDataModel()
        let container = NSPersistentCloudKitContainer(name: "PromptBind", managedObjectModel: model)
        
        // Configure for CloudKit
        let storeDescription = container.persistentStoreDescriptions.first!
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        // Set CloudKit container identifier
        storeDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.samholstein.PromptBind"
        )
        
        container.loadPersistentStores { [weak self] storeDescription, error in
            if let error = error {
                print("Core Data failed to load: \(error.localizedDescription)")
                self?.cloudKitError = error.localizedDescription
                self?.isCloudKitReady = false
            } else {
                print("Core Data loaded successfully")
                self?.isCloudKitReady = true
                self?.cloudKitError = nil
                
                // Enable automatic merging
                container.viewContext.automaticallyMergesChangesFromParent = true
                container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                
                // Watch for CloudKit changes
                NotificationCenter.default.addObserver(
                    forName: .NSPersistentStoreRemoteChange,
                    object: nil,
                    queue: .main
                ) { _ in
                    print("CloudKit remote change detected")
                }
            }
        }
        
        return container
    }()
    
    private func createDataModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        
        // Create Category entity
        let categoryEntity = NSEntityDescription()
        categoryEntity.name = "Category"
        categoryEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        
        let categoryIdAttribute = NSAttributeDescription()
        categoryIdAttribute.name = "id"
        categoryIdAttribute.attributeType = .UUIDAttributeType
        categoryIdAttribute.isOptional = false
        
        let categoryNameAttribute = NSAttributeDescription()
        categoryNameAttribute.name = "name"
        categoryNameAttribute.attributeType = .stringAttributeType
        categoryNameAttribute.isOptional = false
        
        let categoryOrderAttribute = NSAttributeDescription()
        categoryOrderAttribute.name = "order"
        categoryOrderAttribute.attributeType = .integer16AttributeType
        categoryOrderAttribute.isOptional = false
        categoryOrderAttribute.defaultValue = 0
        
        categoryEntity.properties = [categoryIdAttribute, categoryNameAttribute, categoryOrderAttribute]
        
        // Create Prompt entity
        let promptEntity = NSEntityDescription()
        promptEntity.name = "Prompt"
        promptEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        
        let promptIdAttribute = NSAttributeDescription()
        promptIdAttribute.name = "id"
        promptIdAttribute.attributeType = .UUIDAttributeType
        promptIdAttribute.isOptional = false
        
        let promptTriggerAttribute = NSAttributeDescription()
        promptTriggerAttribute.name = "trigger"
        promptTriggerAttribute.attributeType = .stringAttributeType
        promptTriggerAttribute.isOptional = false
        
        let promptExpansionAttribute = NSAttributeDescription()
        promptExpansionAttribute.name = "expansion"
        promptExpansionAttribute.attributeType = .stringAttributeType
        promptExpansionAttribute.isOptional = false
        
        let promptEnabledAttribute = NSAttributeDescription()
        promptEnabledAttribute.name = "enabled"
        promptEnabledAttribute.attributeType = .booleanAttributeType
        promptEnabledAttribute.isOptional = false
        promptEnabledAttribute.defaultValue = true
        
        promptEntity.properties = [promptIdAttribute, promptTriggerAttribute, promptExpansionAttribute, promptEnabledAttribute]
        
        // Create relationships - this is the corrected part
        let categoryPromptsRelationship = NSRelationshipDescription()
        categoryPromptsRelationship.name = "prompts"
        categoryPromptsRelationship.destinationEntity = promptEntity
        categoryPromptsRelationship.minCount = 0
        categoryPromptsRelationship.maxCount = 0 // 0 means "to many"
        categoryPromptsRelationship.deleteRule = .cascadeDeleteRule
        
        let promptCategoryRelationship = NSRelationshipDescription()
        promptCategoryRelationship.name = "category"
        promptCategoryRelationship.destinationEntity = categoryEntity
        promptCategoryRelationship.minCount = 0
        promptCategoryRelationship.maxCount = 1 // "to one"
        promptCategoryRelationship.deleteRule = .nullifyDeleteRule
        
        // Set inverse relationships
        categoryPromptsRelationship.inverseRelationship = promptCategoryRelationship
        promptCategoryRelationship.inverseRelationship = categoryPromptsRelationship
        
        // Add relationships to entities
        categoryEntity.properties.append(categoryPromptsRelationship)
        promptEntity.properties.append(promptCategoryRelationship)
        
        // Add entities to model
        model.entities = [categoryEntity, promptEntity]
        
        return model
    }
    
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
                    self?.isCloudKitReady = true
                    self?.cloudKitError = nil
                    print("CloudKit account available")
                case .noAccount:
                    self?.isCloudKitReady = false
                    self?.cloudKitError = "Not signed into iCloud"
                    print("CloudKit: No iCloud account")
                case .restricted:
                    self?.isCloudKitReady = false
                    self?.cloudKitError = "iCloud account restricted"
                    print("CloudKit: Account restricted")
                case .couldNotDetermine:
                    self?.isCloudKitReady = false
                    self?.cloudKitError = "Could not determine iCloud status"
                    print("CloudKit: Could not determine status")
                case .temporarilyUnavailable:
                    self?.isCloudKitReady = false
                    self?.cloudKitError = "iCloud temporarily unavailable"
                    print("CloudKit: Temporarily unavailable")
                @unknown default:
                    self?.isCloudKitReady = false
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