import CoreData
import Combine

class DataService: ObservableObject {
    private let container: NSPersistentContainer
    @Published var prompts: [Prompt] = []
    
    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
        fetchPrompts()
    }
    
    func fetchPrompts() {
        let request = NSFetchRequest<Prompt>(entityName: "Prompt")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Prompt.trigger, ascending: true)]
        
        do {
            prompts = try container.viewContext.fetch(request)
        } catch {
            print("Error fetching prompts: \(error)")
            prompts = []
        }
    }
    
    func addPrompt(trigger: String, expansion: String) {
        let prompt = Prompt(context: container.viewContext)
        prompt.trigger = trigger
        prompt.expansion = expansion
        prompt.enabled = true
        
        save()
    }
    
    func updatePrompt(_ prompt: Prompt, trigger: String? = nil, expansion: String? = nil, enabled: Bool? = nil) {
        if let trigger = trigger {
            prompt.trigger = trigger
        }
        if let expansion = expansion {
            prompt.expansion = expansion
        }
        if let enabled = enabled {
            prompt.enabled = enabled
        }
        
        save()
    }
    
    func deletePrompt(_ prompt: Prompt) {
        container.viewContext.delete(prompt)
        save()
    }
    
    func togglePrompt(_ prompt: Prompt) {
        prompt.enabled.toggle()
        save()
    }
    
    private func save() {
        if container.viewContext.hasChanges {
            do {
                try container.viewContext.save()
                fetchPrompts() // Refresh the published prompts
            } catch {
                print("Error saving context: \(error)")
            }
        }
    }
}