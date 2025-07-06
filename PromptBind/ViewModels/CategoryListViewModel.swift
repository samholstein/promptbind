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
        // Delete all prompts in this category first
        if let promptsToDelete = category.prompts {
            for prompt in promptsToDelete {
                modelContext.delete(prompt)
            }
        }

        // Delete the category itself
        modelContext.delete(category)
        
        do {
            try modelContext.save()
            loadCategories()
        } catch {
            print("Error deleting category: \(error)")
        }
    }
}