import SwiftUI
import SwiftData

@main
struct PromptBindApp: App {
    let container: ModelContainer
    
    init() {
        do {
            container = try ModelContainer(for: Prompt.self, Category.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(modelContext: container.mainContext)
                .modelContainer(container)
        }
    }
}