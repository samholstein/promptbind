import Foundation
import CoreData

extension NSManagedObject {
    // Prompt-specific extensions for NSManagedObject
    var promptID: UUID {
        get { value(forKey: "id") as? UUID ?? UUID() }
        set { setValue(newValue, forKey: "id") }
    }
    
    var promptTrigger: String {
        get { value(forKey: "trigger") as? String ?? "" }
        set { setValue(newValue, forKey: "trigger") }
    }
    
    var promptExpansion: String {
        get { value(forKey: "expansion") as? String ?? "" }
        set { setValue(newValue, forKey: "expansion") }
    }
    
    var promptEnabled: Bool {
        get { value(forKey: "enabled") as? Bool ?? true }
        set { setValue(newValue, forKey: "enabled") }
    }
    
    var promptCategory: NSManagedObject? {
        get { value(forKey: "category") as? NSManagedObject }
        set { setValue(newValue, forKey: "category") }
    }
    
    // Helper methods for Prompt
    var isPrompt: Bool {
        return entity.name == "Prompt"
    }
    
    var displayName: String {
        guard isPrompt else { return "" }
        return promptTrigger.isEmpty ? "<No Trigger>" : promptTrigger
    }
    
    var previewText: String {
        guard isPrompt else { return "" }
        let expansion = promptExpansion
        if expansion.count > 50 {
            return String(expansion.prefix(47)) + "..."
        }
        return expansion
    }
}

// Convenience methods for creating prompts
extension NSManagedObjectContext {
    func createPrompt(trigger: String, expansion: String, enabled: Bool = true, category: NSManagedObject? = nil) -> NSManagedObject {
        let prompt = NSEntityDescription.insertNewObject(forEntityName: "Prompt", into: self)
        prompt.promptID = UUID()
        prompt.promptTrigger = trigger
        prompt.promptExpansion = expansion
        prompt.promptEnabled = enabled
        prompt.promptCategory = category
        return prompt
    }
}