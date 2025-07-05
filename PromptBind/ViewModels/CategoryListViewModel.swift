import Foundation
import SwiftData
import Combine

class CategoryListViewModel: ObservableObject {
    @Published var categories: [Category] = []
    
    private var modelContext: ModelContext
    private var cancellables = Set<AnyCancellable>()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadCategories()
    }

    func loadCategories() {
        do {
            let descriptor = FetchDescriptor<Category>(sortBy: [SortDescriptor(\.order)])
            self.categories = try modelContext.fetch(descriptor)
            if self.categories.isEmpty {
                // ADD: Create a default "Uncategorized" category if none exist
                let defaultCategory = Category(name: "Uncategorized", order: 0)
                modelContext.insert(defaultCategory)
                try modelContext.save()
                self.categories = [defaultCategory]
            }
        } catch {
            print("Error loading categories: \(error)")
            self.categories = []
        }
    }

    func addCategory(name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("Category name cannot be empty.")
            return
        }
        guard !categories.contains(where: { $0.name == name }) else {
            print("Category with name '\(name)' already exists.")
            return
        }

        let newOrder = (categories.map { $0.order }.max() ?? -1) + 1
        
        let newCategory = Category(name: name, order: newOrder)
        modelContext.insert(newCategory)
        do {
            try modelContext.save()
            loadCategories()
        } catch {
            print("Error saving new category: \(error)")
        }
    }

    func renameCategory(_ category: Category, newName: String) {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("New category name cannot be empty.")
            return
        }
        guard !categories.contains(where: { $0.id != category.id && $0.name == newName }) else {
            print("Another category with name '\(newName)' already exists.")
            return
        }

        category.name = newName
        do {
            try modelContext.save()
            loadCategories()
        } catch {
            print("Error renaming category: \(error)")
        }
    }
    
    func reorderCategories(from sourceIndex: IndexSet, to destinationIndex: Int) {
        var reorderedCategories = categories
        reorderedCategories.move(fromOffsets: sourceIndex, toOffset: destinationIndex)

        for (index, category) in reorderedCategories.enumerated() {
            category.order = Int16(index)
        }
        
        do {
            try modelContext.save()
            loadCategories()
        } catch {
            print("Error saving reordered categories: \(error)")
        }
    }

    func deleteCategory(_ category: Category) {
        // Find the "Uncategorized" category or create it if it doesn't exist
        var uncategorized: Category?
        do {
            let descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.name == "Uncategorized" })
            uncategorized = try modelContext.fetch(descriptor).first
            if uncategorized == nil {
                uncategorized = Category(name: "Uncategorized", order: (categories.map { $0.order }.max() ?? -1) + 1)
                modelContext.insert(uncategorized!)
            }
        } catch {
            print("Error finding or creating Uncategorized category: \(error)")
            // If we can't get an uncategorized category, we can't reassign prompts, so we'll just delete them.
        }

        // Reassign prompts from the deleted category to "Uncategorized"
        if let promptsToReassign = category.prompts {
            for prompt in promptsToReassign {
                if let uncategorized = uncategorized {
                    prompt.category = uncategorized
                } else {
                    // If no uncategorized category, delete the prompt.
                    modelContext.delete(prompt)
                }
            }
        }

        modelContext.delete(category)
        do {
            try modelContext.save()
            loadCategories()
        } catch {
            print("Error deleting category: \(error)")
        }
    }
}