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
        get { value(forKey: "prompt") as? String ?? "" }  // Changed from "expansion" to "prompt"
        set { setValue(newValue, forKey: "prompt") }       // Changed from "expansion" to "prompt"
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
        return promptTrigger.isEmpty ? "<No Bind>" : promptTrigger  // Updated terminology
    }
    
    var previewText: String {
        guard isPrompt else { return "" }
        let prompt = promptExpansion  // This now refers to the "prompt" field
        if prompt.count > 50 {
            return String(prompt.prefix(47)) + "..."
        }
        return prompt
    }
}

// Convenience methods for creating prompts
extension NSManagedObjectContext {
    func createPrompt(trigger: String, expansion: String, enabled: Bool = true, category: NSManagedObject? = nil) -> NSManagedObject {
        let prompt = NSEntityDescription.insertNewObject(forEntityName: "Prompt", into: self)
        prompt.promptID = UUID()
        prompt.promptTrigger = trigger
        prompt.promptExpansion = expansion  // This will now save to the "prompt" field
        prompt.promptEnabled = enabled
        prompt.promptCategory = category
        return prompt
    }
}