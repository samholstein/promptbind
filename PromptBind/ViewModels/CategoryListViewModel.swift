import Foundation
import CoreData
import Combine

class CategoryListViewModel: ObservableObject {
    @Published var categories: [NSManagedObject] = []
    @Published var selectedCategory: NSManagedObject?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var viewContext: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()
    
    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
        setupNotifications()
        loadCategories()
    }
    
    private func setupNotifications() {
        // Listen for Core Data changes
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.loadCategories()
                }
            }
            .store(in: &cancellables)
    }
    
    func loadCategories() {
        isLoading = true
        errorMessage = nil
        
        let request = NSFetchRequest<NSManagedObject>(entityName: "Category")
        request.sortDescriptors = [
            NSSortDescriptor(key: "order", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]
        
        do {
            self.categories = try viewContext.fetch(request)
            print("CategoryListViewModel: Loaded \(categories.count) categories")
        } catch {
            print("CategoryListViewModel: Error loading categories: \(error)")
            self.errorMessage = "Failed to load categories: \(error.localizedDescription)"
            self.categories = []
        }
        
        isLoading = false
    }
    
    func addCategory(name: String, order: Int16 = 0) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Category name cannot be empty"
            return
        }
        
        // Check for duplicate names
        let existingCategory = categories.first { category in
            category.categoryName.lowercased() == name.lowercased()
        }
        
        if existingCategory != nil {
            errorMessage = "A category with this name already exists"
            return
        }
        
        do {
            let newCategory = viewContext.createCategory(name: name, order: order)
            try viewContext.save()
            print("CategoryListViewModel: Added new category: \(name)")
            loadCategories()
        } catch {
            print("CategoryListViewModel: Error adding category: \(error)")
            errorMessage = "Failed to add category: \(error.localizedDescription)"
        }
    }
    
    func updateCategory(_ category: NSManagedObject, newName: String?, newOrder: Int16?) {
        var hasChanges = false
        
        if let name = newName?.trimmingCharacters(in: .whitespacesAndNewlines), 
           !name.isEmpty, 
           category.categoryName != name {
            
            // Check for duplicate names (excluding current category)
            let existingCategory = categories.first { otherCategory in
                otherCategory.objectID != category.objectID && 
                otherCategory.categoryName.lowercased() == name.lowercased()
            }
            
            if existingCategory != nil {
                errorMessage = "A category with this name already exists"
                return
            }
            
            category.categoryName = name
            hasChanges = true
        }
        
        if let order = newOrder, category.categoryOrder != order {
            category.categoryOrder = order
            hasChanges = true
        }
        
        if hasChanges {
            do {
                try viewContext.save()
                print("CategoryListViewModel: Updated category")
                loadCategories()
            } catch {
                print("CategoryListViewModel: Error updating category: \(error)")
                errorMessage = "Failed to update category: \(error.localizedDescription)"
            }
        }
    }
    
    func deleteCategory(_ category: NSManagedObject) {
        // Check if category has prompts
        let promptCount = category.categoryPrompts.count
        if promptCount > 0 {
            errorMessage = "Cannot delete category with \(promptCount) prompt\(promptCount == 1 ? "" : "s"). Move or delete the prompts first."
            return
        }
        
        do {
            viewContext.delete(category)
            try viewContext.save()
            print("CategoryListViewModel: Deleted category")
            
            // Clear selection if we deleted the selected category
            if selectedCategory?.objectID == category.objectID {
                selectedCategory = nil
            }
            
            loadCategories()
        } catch {
            print("CategoryListViewModel: Error deleting category: \(error)")
            errorMessage = "Failed to delete category: \(error.localizedDescription)"
        }
    }
    
    func selectCategory(_ category: NSManagedObject?) {
        selectedCategory = category
    }
    
    func clearError() {
        errorMessage = nil
    }
    
    deinit {
        cancellables.removeAll()
    }
}