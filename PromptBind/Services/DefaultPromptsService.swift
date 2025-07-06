import Foundation
import SwiftData

struct DefaultPromptsData: Codable {
    let schemaVersion: String
    let categories: [DefaultCategory]
    let prompts: [DefaultPrompt]
}

struct DefaultCategory: Codable {
    let name: String
    let order: Int
}

struct DefaultPrompt: Codable {
    let id: String
    let trigger: String
    let content: String
    let categoryName: String
    let enabled: Bool
    
    init(id: String = UUID().uuidString, trigger: String, content: String, categoryName: String, enabled: Bool = true) {
        self.id = id
        self.trigger = trigger
        self.content = content
        self.categoryName = categoryName
        self.enabled = enabled
    }
}

class DefaultPromptsService {
    static let shared = DefaultPromptsService()
    private init() {}
    
    func loadDefaultPrompts() -> DefaultPromptsData? {
        guard let url = Bundle.main.url(forResource: "DefaultPrompts", withExtension: "json") else {
            print("DefaultPrompts.json not found in bundle")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            let defaultPrompts = try JSONDecoder().decode(DefaultPromptsData.self, from: data)
            print("Successfully loaded \(defaultPrompts.prompts.count) default prompts")
            return defaultPrompts
        } catch {
            print("Failed to load default prompts: \(error)")
            return nil
        }
    }
    
    func addDefaultPromptsToContext(_ modelContext: ModelContext) {
        guard let defaultData = loadDefaultPrompts() else {
            print("No default prompts data available")
            return
        }
        
        // Create categories first
        var categoryMap: [String: Category] = [:]
        
        for defaultCategory in defaultData.categories {
            // Check if category already exists
            let descriptor = FetchDescriptor<Category>(predicate: #Predicate<Category> { $0.name == defaultCategory.name })
            
            do {
                let existingCategories = try modelContext.fetch(descriptor)
                if let existingCategory = existingCategories.first {
                    categoryMap[defaultCategory.name] = existingCategory
                } else {
                    let newCategory = Category(name: defaultCategory.name, order: Int16(defaultCategory.order))
                    modelContext.insert(newCategory)
                    categoryMap[defaultCategory.name] = newCategory
                }
            } catch {
                print("Error checking for existing category: \(error)")
            }
        }
        
        // Create prompts
        for defaultPrompt in defaultData.prompts {
            // Check if prompt with this trigger already exists
            let descriptor = FetchDescriptor<Prompt>(predicate: #Predicate<Prompt> { $0.trigger == defaultPrompt.trigger })
            
            do {
                let existingPrompts = try modelContext.fetch(descriptor)
                if existingPrompts.isEmpty {
                    let newPrompt = Prompt(trigger: defaultPrompt.trigger, 
                                         expansion: defaultPrompt.content, 
                                         enabled: defaultPrompt.enabled)
                    
                    // Assign to category
                    if let category = categoryMap[defaultPrompt.categoryName] {
                        newPrompt.category = category
                    }
                    
                    modelContext.insert(newPrompt)
                    print("Added default prompt: \(defaultPrompt.trigger)")
                } else {
                    print("Prompt with trigger '\(defaultPrompt.trigger)' already exists, skipping")
                }
            } catch {
                print("Error checking for existing prompt: \(error)")
            }
        }
        
        // Save all changes
        do {
            try modelContext.save()
            print("Successfully saved default prompts to database")
        } catch {
            print("Error saving default prompts: \(error)")
        }
    }
}