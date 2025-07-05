import CoreData

struct PersistenceController {
    static let shared = PersistenceController()
    
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "CoreDataModel")
        
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores { description, error in
            if let error = error {
                print("Core Data failed to load: \(error)")
            }
        }
        
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
    
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        
        // Add sample data for previews
        let viewContext = controller.container.viewContext
        
        let samplePrompt = Prompt(context: viewContext)
        samplePrompt.trigger = ";hello"
        samplePrompt.expansion = "Hello, world!"
        samplePrompt.enabled = true
        
        let samplePrompt2 = Prompt(context: viewContext)
        samplePrompt2.trigger = ";date"
        samplePrompt2.expansion = "Current date: {date}"
        samplePrompt2.enabled = true
        
        try? viewContext.save()
        
        return controller
    }()
}