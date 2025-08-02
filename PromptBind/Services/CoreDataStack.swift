import Foundation
import CoreData
import CloudKit
import Combine

class CoreDataStack: ObservableObject {
    static let shared = CoreDataStack()
    
    @Published var isCloudKitReady = false
    @Published var cloudKitError: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    lazy var persistentContainer: NSPersistentCloudKitContainer = {
        let model = NSManagedObjectModel()
        
        // Create Category entity
        let categoryEntity = NSEntityDescription()
        categoryEntity.name = "Category"
        categoryEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        
        let categoryId = NSAttributeDescription()
        categoryId.name = "id"
        categoryId.attributeType = .UUIDAttributeType
        categoryId.isOptional = true
        categoryId.defaultValue = UUID()
        
        let categoryName = NSAttributeDescription()
        categoryName.name = "name"
        categoryName.attributeType = .stringAttributeType
        categoryName.isOptional = true
        categoryName.defaultValue = ""
        
        let categoryOrder = NSAttributeDescription()
        categoryOrder.name = "order"
        categoryOrder.attributeType = .integer16AttributeType
        categoryOrder.isOptional = true
        categoryOrder.defaultValue = 0
        
        categoryEntity.properties = [categoryId, categoryName, categoryOrder]
        
        // Create Prompt entity
        let promptEntity = NSEntityDescription()
        promptEntity.name = "Prompt"
        promptEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        
        let promptId = NSAttributeDescription()
        promptId.name = "id"
        promptId.attributeType = .UUIDAttributeType
        promptId.isOptional = true
        promptId.defaultValue = UUID()
        
        let promptTrigger = NSAttributeDescription()
        promptTrigger.name = "trigger"
        promptTrigger.attributeType = .stringAttributeType
        promptTrigger.isOptional = true
        promptTrigger.defaultValue = ""
        
        let promptExpansion = NSAttributeDescription()
        promptExpansion.name = "prompt"
        promptExpansion.attributeType = .stringAttributeType
        promptExpansion.isOptional = true
        promptExpansion.defaultValue = ""
        
        let promptEnabled = NSAttributeDescription()
        promptEnabled.name = "enabled"
        promptEnabled.attributeType = .booleanAttributeType
        promptEnabled.isOptional = true
        promptEnabled.defaultValue = true
        
        promptEntity.properties = [promptId, promptTrigger, promptExpansion, promptEnabled]
        
        // Create Subscription entity
        let subscriptionEntity = NSEntityDescription()
        subscriptionEntity.name = "Subscription"
        subscriptionEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        
        let subscriptionId = NSAttributeDescription()
        subscriptionId.name = "id"
        subscriptionId.attributeType = .UUIDAttributeType
        subscriptionId.isOptional = true
        subscriptionId.defaultValue = UUID()
        
        let subscriptionDeviceId = NSAttributeDescription()
        subscriptionDeviceId.name = "deviceId"
        subscriptionDeviceId.attributeType = .stringAttributeType
        subscriptionDeviceId.isOptional = true
        subscriptionDeviceId.defaultValue = ""
        
        let subscriptionStatus = NSAttributeDescription()
        subscriptionStatus.name = "status"
        subscriptionStatus.attributeType = .stringAttributeType
        subscriptionStatus.isOptional = true
        subscriptionStatus.defaultValue = "free"
        
        let subscriptionCustomerId = NSAttributeDescription()
        subscriptionCustomerId.name = "customerId"
        subscriptionCustomerId.attributeType = .stringAttributeType
        subscriptionCustomerId.isOptional = true
        
        let subscriptionStripeSubscriptionId = NSAttributeDescription()
        subscriptionStripeSubscriptionId.name = "stripeSubscriptionId"
        subscriptionStripeSubscriptionId.attributeType = .stringAttributeType
        subscriptionStripeSubscriptionId.isOptional = true
        
        let subscriptionExpiresAt = NSAttributeDescription()
        subscriptionExpiresAt.name = "expiresAt"
        subscriptionExpiresAt.attributeType = .dateAttributeType
        subscriptionExpiresAt.isOptional = true
        
        let subscriptionLastChecked = NSAttributeDescription()
        subscriptionLastChecked.name = "lastChecked"
        subscriptionLastChecked.attributeType = .dateAttributeType
        subscriptionLastChecked.isOptional = true
        subscriptionLastChecked.defaultValue = Date()
        
        let subscriptionCreatedAt = NSAttributeDescription()
        subscriptionCreatedAt.name = "createdAt"
        subscriptionCreatedAt.attributeType = .dateAttributeType
        subscriptionCreatedAt.isOptional = true
        subscriptionCreatedAt.defaultValue = Date()
        
        let subscriptionUpdatedAt = NSAttributeDescription()
        subscriptionUpdatedAt.name = "updatedAt"
        subscriptionUpdatedAt.attributeType = .dateAttributeType
        subscriptionUpdatedAt.isOptional = true
        subscriptionUpdatedAt.defaultValue = Date()
        
        subscriptionEntity.properties = [
            subscriptionId,
            subscriptionDeviceId,
            subscriptionStatus,
            subscriptionCustomerId,
            subscriptionStripeSubscriptionId,
            subscriptionExpiresAt,
            subscriptionLastChecked,
            subscriptionCreatedAt,
            subscriptionUpdatedAt
        ]
        
        // Create relationship between Category and Prompt
        let categoryPromptsRelationship = NSRelationshipDescription()
        categoryPromptsRelationship.name = "prompts"
        categoryPromptsRelationship.destinationEntity = promptEntity
        categoryPromptsRelationship.minCount = 0
        categoryPromptsRelationship.maxCount = 0
        categoryPromptsRelationship.deleteRule = .cascadeDeleteRule
        categoryPromptsRelationship.isOptional = true
        
        let promptCategoryRelationship = NSRelationshipDescription()
        promptCategoryRelationship.name = "category"
        promptCategoryRelationship.destinationEntity = categoryEntity
        promptCategoryRelationship.minCount = 0
        promptCategoryRelationship.maxCount = 1
        promptCategoryRelationship.deleteRule = .nullifyDeleteRule
        promptCategoryRelationship.isOptional = true
        
        categoryPromptsRelationship.inverseRelationship = promptCategoryRelationship
        promptCategoryRelationship.inverseRelationship = categoryPromptsRelationship
        
        categoryEntity.properties.append(categoryPromptsRelationship)
        promptEntity.properties.append(promptCategoryRelationship)
        
        model.entities = [categoryEntity, promptEntity, subscriptionEntity]
        
        let container = NSPersistentCloudKitContainer(name: "PromptBind", managedObjectModel: model)
        
        guard let storeDescription = container.persistentStoreDescriptions.first else {
            fatalError("Failed to get persistent store description")
        }
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        storeDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.samholstein.PromptBind"
        )
        
        container.loadPersistentStores { [weak self] storeDescription, error in
            if let error = error {
                print("Core Data failed to load: \(error.localizedDescription)")
                self?.cloudKitError = "Core Data initialization failed: \(error.localizedDescription)"
                self?.isCloudKitReady = false
            } else {
                print("Core Data loaded successfully!")
                self?.isCloudKitReady = true
                self?.cloudKitError = nil
                
                container.viewContext.automaticallyMergesChangesFromParent = true
                container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                
                self?.monitorCloudKitEvents()
                self?.updatePromptCount()
            }
        }
        
        return container
    }()
    
    var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    private init() {
        // Initialization is handled by the lazy var
    }

    func save() {
        if viewContext.hasChanges {
            do {
                try viewContext.save()
                updatePromptCount()
            } catch {
                print("Core Data save error: \(error.localizedDescription)")
            }
        }
    }
    
    private func monitorCloudKitEvents() {
        NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
                    return
                }
                
                // We only care about events that have finished and were successful
                guard event.endDate != nil, event.error == nil else {
                    return
                }

                if event.type == .import {
                    print("CoreDataStack: Import finished, updating prompt count and subscription.")
                    self?.updatePromptCount()
                    Task { @MainActor in
                        SubscriptionManager.shared.syncSubscriptionFromCloudKit()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Subscription and Prompt Count
    
    func promptCount() -> Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
        do {
            return try viewContext.count(for: request)
        } catch {
            print("CoreDataStack: Error counting prompts: \(error)")
            return 0
        }
    }
    
    private func updatePromptCount() {
        Task { @MainActor in
            let count = promptCount()
            SubscriptionManager.shared.updatePromptCount(count)
        }
    }

    // MARK: - Subscription Entity Management
    
    func getDeviceSubscription() -> NSManagedObject? {
        let deviceId = DeviceIdentificationService.shared.getDeviceID()
        let request = NSFetchRequest<NSManagedObject>(entityName: "Subscription")
        request.predicate = NSPredicate(format: "deviceId == %@", deviceId)
        request.fetchLimit = 1
        
        do {
            return try viewContext.fetch(request).first
        } catch {
            print("CoreDataStack: Error fetching device subscription: \(error)")
            return nil
        }
    }
    
    func getAllSubscriptions() -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Subscription")
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("CoreDataStack: Error fetching all subscriptions: \(error)")
            return []
        }
    }
    
    func saveSubscription(
        deviceId: String,
        status: String,
        customerId: String? = nil,
        stripeSubscriptionId: String? = nil,
        expiresAt: Date? = nil
    ) -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Subscription")
        request.predicate = NSPredicate(format: "deviceId == %@", deviceId)
        request.fetchLimit = 1
        
        let subscription: NSManagedObject
        
        do {
            if let existingSubscription = try viewContext.fetch(request).first {
                subscription = existingSubscription
            } else {
                subscription = NSEntityDescription.insertNewObject(forEntityName: "Subscription", into: viewContext)
                subscription.setValue(UUID(), forKey: "id")
                subscription.setValue(deviceId, forKey: "deviceId")
                subscription.setValue(Date(), forKey: "createdAt")
            }
        } catch {
            subscription = NSEntityDescription.insertNewObject(forEntityName: "Subscription", into: viewContext)
            subscription.setValue(UUID(), forKey: "id")
            subscription.setValue(deviceId, forKey: "deviceId")
            subscription.setValue(Date(), forKey: "createdAt")
        }
        
        subscription.setValue(status, forKey: "status")
        subscription.setValue(customerId, forKey: "customerId")
        subscription.setValue(stripeSubscriptionId, forKey: "stripeSubscriptionId")
        subscription.setValue(expiresAt, forKey: "expiresAt")
        subscription.setValue(Date(), forKey: "lastChecked")
        subscription.setValue(Date(), forKey: "updatedAt")
        
        save()
        return subscription
    }
}