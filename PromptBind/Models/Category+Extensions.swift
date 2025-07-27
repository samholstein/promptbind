import Foundation
import CoreData

extension NSManagedObject {
    // Category-specific extensions for NSManagedObject
    var categoryID: UUID {
        get { value(forKey: "id") as? UUID ?? UUID() }
        set { setValue(newValue, forKey: "id") }
    }
    
    var categoryName: String {
        get { value(forKey: "name") as? String ?? "" }
        set { setValue(newValue, forKey: "name") }
    }
    
    var categoryOrder: Int16 {
        get { value(forKey: "order") as? Int16 ?? 0 }
        set { setValue(newValue, forKey: "order") }
    }
    
    var categoryPrompts: Set<NSManagedObject> {
        get { value(forKey: "prompts") as? Set<NSManagedObject> ?? Set() }
        set { setValue(newValue, forKey: "prompts") }
    }
    
    // Helper methods for Category
    var isCategory: Bool {
        return entity.name == "Category"
    }
    
    func addPromptToCategory(_ prompt: NSManagedObject) {
        guard isCategory else { return }
        var prompts = categoryPrompts
        prompts.insert(prompt)
        categoryPrompts = prompts
        prompt.setValue(self, forKey: "category")
    }
    
    func removePromptFromCategory(_ prompt: NSManagedObject) {
        guard isCategory else { return }
        var prompts = categoryPrompts
        prompts.remove(prompt)
        categoryPrompts = prompts
        prompt.setValue(nil, forKey: "category")
    }
}

// Convenience methods for creating categories
extension NSManagedObjectContext {
    func createCategory(name: String, order: Int16 = 0) -> NSManagedObject {
        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: self)
        category.categoryID = UUID()
        category.categoryName = name
        category.categoryOrder = order
        return category
    }
}