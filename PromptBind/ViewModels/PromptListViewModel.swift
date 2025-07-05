import Foundation
import Combine
import CoreData 

class PromptListViewModel: ObservableObject {
    @Published var prompts: [PromptItem] = []
    @Published var selectedCategory: Category? {
        didSet {
            loadPrompts() 
        }
    }
    
    private let dataService: DataService
    private var cancellables = Set<AnyCancellable>()

    init(dataService: DataService = DataServiceImpl()) {
        self.dataService = dataService
        loadPrompts()
    }

    func loadPrompts() {
        do {
            let allPrompts = try dataService.fetchPrompts()
            if let category = selectedCategory {
                self.prompts = allPrompts.filter { $0.category?.objectID == category.objectID }
                                      .sorted { ($0.trigger ?? "") < ($1.trigger ?? "") }
            } else {
                self.prompts = allPrompts.sorted { ($0.trigger ?? "") < ($1.trigger ?? "") }
            }
        } catch {
            print("Error loading prompts: \(error)")
            self.prompts = []
        }
    }

    func addPrompt(trigger: String, content: String, category: Category?) {
        guard let currentCategory = category ?? selectedCategory else {
            print("Cannot add prompt: No category selected or provided.")
            return
        }
        guard !trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("Prompt trigger cannot be empty.")
            return
        }
         guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("Prompt content cannot be empty.")
            return
        }
        do {
            let allPrompts = try dataService.fetchPrompts() 
            if allPrompts.contains(where: { $0.trigger == trigger }) {
                print("Prompt with trigger '\(trigger)' already exists.")
                return
            }
        } catch {
            print("Error checking for duplicate triggers: \(error)")
        }

        let backgroundContext = dataService.newBackgroundContext()
        backgroundContext.performAndWait {
            guard let categoryInContext = backgroundContext.object(with: currentCategory.objectID) as? Category else {
                print("Failed to fetch category in background context.")
                return
            }

            let newPrompt = PromptItem(context: backgroundContext)
            newPrompt.id = UUID()
            newPrompt.trigger = trigger
            newPrompt.content = content
            newPrompt.category = categoryInContext
            
            do {
                try backgroundContext.save()
                DispatchQueue.main.async {
                    self.loadPrompts() 
                }
            } catch {
                print("Error saving new prompt: \(error)")
            }
        }
    }

    func updatePrompt(_ prompt: PromptItem, newTrigger: String?, newContent: String?, newCategory: Category?) {
        guard let context = prompt.managedObjectContext else {
            print("Prompt has no context to save.")
            return
        }

        var hasChanges = false
        context.performAndWait {
            if let trigger = newTrigger, !trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, prompt.trigger != trigger {
                do {
                    let allPrompts = try self.dataService.fetchPrompts(context: context)
                    if allPrompts.contains(where: { $0.objectID != prompt.objectID && $0.trigger == trigger }) {
                        print("Another prompt with trigger '\(trigger)' already exists.")
                        return 
                    }
                    prompt.trigger = trigger
                    hasChanges = true
                } catch {
                     print("Error checking for duplicate triggers during update: \(error)")
                }
            }
            if let content = newContent, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, prompt.content != content {
                prompt.content = content
                hasChanges = true
            }
            if let category = newCategory, prompt.category?.objectID != category.objectID {
                if let categoryInContext = context.object(with: category.objectID) as? Category {
                    prompt.category = categoryInContext
                    hasChanges = true
                } else {
                    print("Failed to fetch new category in prompt's context for update.")
                }
            }

            if hasChanges {
                do {
                    if context.hasChanges { 
                         try context.save()
                    }
                    DispatchQueue.main.async {
                        self.loadPrompts()
                    }
                } catch {
                    print("Error updating prompt: \(error)")
                }
            }
        }
    }

    func deletePrompt(_ prompt: PromptItem) {
        do {
            try dataService.delete(prompts: [prompt])
            loadPrompts()
        } catch {
            print("Error deleting prompt: \(error)")
        }
    }
}