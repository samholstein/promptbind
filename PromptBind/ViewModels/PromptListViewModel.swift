import Foundation
import SwiftData
import Combine

class PromptListViewModel: ObservableObject {
    @Published var prompts: [Prompt] = []
    @Published var selectedCategory: Category? {
        didSet {
            loadPrompts()
        }
    }
    
    private var modelContext: ModelContext
    private var cancellables = Set<AnyCancellable>()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadPrompts()
    }

    func loadPrompts() {
        do {
            let descriptor = FetchDescriptor<Prompt>(sortBy: [SortDescriptor(\.trigger)])
            let allPrompts = try modelContext.fetch(descriptor)
            
            if let category = selectedCategory {
                self.prompts = allPrompts.filter { $0.category?.id == category.id }
            } else {
                // If no category is selected, show all prompts
                self.prompts = allPrompts
            }
            
            // Debug logging to help track filtering
            print("Selected category: \(selectedCategory?.name ?? "None")")
            print("Total prompts: \(allPrompts.count)")
            print("Filtered prompts: \(self.prompts.count)")
        } catch {
            print("Error loading prompts: \(error)")
            self.prompts = []
        }
    }

    func addPrompt(trigger: String, expansion: String, category: Category?) {
        guard !trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("Prompt trigger cannot be empty.")
            return
        }
         guard !expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("Prompt expansion cannot be empty.")
            return
        }
        
        do {
            let descriptor = FetchDescriptor<Prompt>(predicate: #Predicate { $0.trigger == trigger })
            let existingPrompts = try modelContext.fetch(descriptor)
            if !existingPrompts.isEmpty {
                print("Prompt with trigger '\(trigger)' already exists.")
                return
            }
        } catch {
            print("Error checking for duplicate triggers: \(error)")
        }

        let newPrompt = Prompt(trigger: trigger, expansion: expansion)
        newPrompt.category = category ?? selectedCategory
        modelContext.insert(newPrompt)
        
        do {
            try modelContext.save()
            loadPrompts()
        } catch {
            print("Error saving new prompt: \(error)")
        }
    }

    func updatePrompt(_ prompt: Prompt, newTrigger: String?, newExpansion: String?, newCategory: Category?) {
        var hasChanges = false

        if let trigger = newTrigger, !trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, prompt.trigger != trigger {
            do {
                let descriptor = FetchDescriptor<Prompt>(predicate: #Predicate { $0.trigger == trigger })
                let existingPrompts = try modelContext.fetch(descriptor)
                if existingPrompts.contains(where: { $0.id != prompt.id }) {
                    print("Another prompt with trigger '\(trigger)' already exists.")
                    return
                }
                prompt.trigger = trigger
                hasChanges = true
            } catch {
                 print("Error checking for duplicate triggers during update: \(error)")
            }
        }
        if let expansion = newExpansion, !expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, prompt.expansion != expansion {
            prompt.expansion = expansion
            hasChanges = true
        }
        if let category = newCategory, prompt.category?.id != category.id {
            prompt.category = category
            hasChanges = true
        }

        if hasChanges {
            do {
                try modelContext.save()
                loadPrompts()
            } catch {
                print("Error updating prompt: \(error)")
            }
        }
    }

    func deletePrompt(_ prompt: Prompt) {
        modelContext.delete(prompt)
        do {
            try modelContext.save()
            loadPrompts()
        } catch {
            print("Error deleting prompt: \(error)")
        }
    }
}