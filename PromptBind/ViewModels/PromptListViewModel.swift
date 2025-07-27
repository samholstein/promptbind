import Foundation
import CoreData
import Combine

class PromptListViewModel: ObservableObject {
    @Published var prompts: [NSManagedObject] = []
    @Published var filteredPrompts: [NSManagedObject] = []
    @Published var selectedCategory: NSManagedObject? {
        didSet {
            filterPrompts()
        }
    }
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = "" {
        didSet {
            filterPrompts()
        }
    }
    
    private var viewContext: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()
    
    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
        setupNotifications()
        loadPrompts()
    }
    
    private func setupNotifications() {
        // Listen for Core Data changes
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.loadPrompts()
                }
            }
            .store(in: &cancellables)
    }
    
    func loadPrompts() {
        isLoading = true
        errorMessage = nil
        
        let request = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
        request.sortDescriptors = [NSSortDescriptor(key: "trigger", ascending: true)]
        
        do {
            self.prompts = try viewContext.fetch(request)
            print("PromptListViewModel: Loaded \(prompts.count) prompts")
            filterPrompts()
        } catch {
            print("PromptListViewModel: Error loading prompts: \(error)")
            self.errorMessage = "Failed to load prompts: \(error.localizedDescription)"
            self.prompts = []
            self.filteredPrompts = []
        }
        
        isLoading = false
    }
    
    private func filterPrompts() {
        var filtered = prompts
        
        // Filter by category
        if let category = selectedCategory {
            filtered = filtered.filter { prompt in
                prompt.promptCategory?.objectID == category.objectID
            }
        }
        
        // Filter by search text
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let searchTerm = searchText.lowercased()
            filtered = filtered.filter { prompt in
                prompt.promptTrigger.lowercased().contains(searchTerm) ||
                prompt.promptExpansion.lowercased().contains(searchTerm)
            }
        }
        
        self.filteredPrompts = filtered
        print("PromptListViewModel: Filtered to \(filteredPrompts.count) prompts")
    }
    
    func addPrompt(trigger: String, expansion: String, enabled: Bool = true, category: NSManagedObject? = nil) {
        let trimmedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExpansion = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedTrigger.isEmpty else {
            errorMessage = "Prompt trigger cannot be empty"
            return
        }
        
        guard !trimmedExpansion.isEmpty else {
            errorMessage = "Prompt expansion cannot be empty"
            return
        }
        
        // Check for duplicate trigger
        let existingPrompt = prompts.first { prompt in
            prompt.promptTrigger.lowercased() == trimmedTrigger.lowercased()
        }
        
        if existingPrompt != nil {
            errorMessage = "A prompt with trigger '\(trimmedTrigger)' already exists"
            return
        }
        
        do {
            let newPrompt = viewContext.createPrompt(
                trigger: trimmedTrigger,
                expansion: trimmedExpansion,
                enabled: enabled,
                category: category ?? selectedCategory
            )
            
            try viewContext.save()
            print("PromptListViewModel: Added new prompt: \(trimmedTrigger)")
            loadPrompts()
        } catch {
            print("PromptListViewModel: Error adding prompt: \(error)")
            errorMessage = "Failed to add prompt: \(error.localizedDescription)"
        }
    }
    
    func updatePrompt(_ prompt: NSManagedObject, newTrigger: String?, newExpansion: String?, newEnabled: Bool?, newCategory: NSManagedObject?) {
        var hasChanges = false
        
        if let trigger = newTrigger?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trigger.isEmpty,
           prompt.promptTrigger != trigger {
            
            // Check for duplicate trigger (excluding current prompt)
            let existingPrompt = prompts.first { otherPrompt in
                otherPrompt.objectID != prompt.objectID &&
                otherPrompt.promptTrigger.lowercased() == trigger.lowercased()
            }
            
            if existingPrompt != nil {
                errorMessage = "A prompt with trigger '\(trigger)' already exists"
                return
            }
            
            prompt.promptTrigger = trigger
            hasChanges = true
        }
        
        if let expansion = newExpansion?.trimmingCharacters(in: .whitespacesAndNewlines),
           !expansion.isEmpty,
           prompt.promptExpansion != expansion {
            prompt.promptExpansion = expansion
            hasChanges = true
        }
        
        if let enabled = newEnabled, prompt.promptEnabled != enabled {
            prompt.promptEnabled = enabled
            hasChanges = true
        }
        
        if let category = newCategory, prompt.promptCategory?.objectID != category.objectID {
            prompt.promptCategory = category
            hasChanges = true
        }
        
        if hasChanges {
            do {
                try viewContext.save()
                print("PromptListViewModel: Updated prompt")
                loadPrompts()
            } catch {
                print("PromptListViewModel: Error updating prompt: \(error)")
                errorMessage = "Failed to update prompt: \(error.localizedDescription)"
            }
        }
    }
    
    func deletePrompt(_ prompt: NSManagedObject) {
        do {
            viewContext.delete(prompt)
            try viewContext.save()
            print("PromptListViewModel: Deleted prompt")
            loadPrompts()
        } catch {
            print("PromptListViewModel: Error deleting prompt: \(error)")
            errorMessage = "Failed to delete prompt: \(error.localizedDescription)"
        }
    }
    
    func togglePromptEnabled(_ prompt: NSManagedObject) {
        updatePrompt(prompt, newTrigger: nil, newExpansion: nil, newEnabled: !prompt.promptEnabled, newCategory: nil)
    }
    
    func setSelectedCategory(_ category: NSManagedObject?) {
        selectedCategory = category
    }
    
    func clearSearch() {
        searchText = ""
    }
    
    func clearError() {
        errorMessage = nil
    }
    
    deinit {
        cancellables.removeAll()
    }
}