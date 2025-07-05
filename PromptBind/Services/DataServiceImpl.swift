import Foundation
import CoreData

class DataServiceImpl: DataService {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
    }

    var viewContext: NSManagedObjectContext {
        return container.viewContext
    }
    
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy // As per TRD
        return context
    }

    func fetchPrompts() throws -> [PromptItem] {
        let request: NSFetchRequest<PromptItem> = PromptItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PromptItem.trigger, ascending: true)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("Failed to fetch prompts: \(error)")
            throw error
        }
    }

    func fetchCategories() throws -> [Category] {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Category.order, ascending: true)]
        do {
            return try viewContext.fetch(request)
        } catch {
            print("Failed to fetch categories: \(error)")
            throw error
        }
    }
    
    func saveContext() throws {
        let context = viewContext 
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Failed to save context: \(error)")
                throw error
            }
        }
    }

    func delete(prompts: [PromptItem]) throws {
        let context = viewContext 
        for prompt in prompts {
            context.delete(prompt)
        }
        try saveContext()
    }

    func delete(categories: [Category]) throws {
        let context = viewContext // Or better, get objectIDs and delete on background context
        for category in categories {
            if let promptsInCategory = category.prompts as? Set<PromptItem> {
                for prompt in promptsInCategory {
                    context.delete(prompt) 
                }
            }
            context.delete(category)
        }
        try saveContext()
    }
    
    // Implementation of protocol extension methods
    func fetchPrompts(context: NSManagedObjectContext) throws -> [PromptItem] {
        let request: NSFetchRequest<PromptItem> = PromptItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PromptItem.trigger, ascending: true)]
        return try context.fetch(request)
    }

    func fetchCategories(context: NSManagedObjectContext) throws -> [Category] {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Category.order, ascending: true)]
        return try context.fetch(request)
    }
}