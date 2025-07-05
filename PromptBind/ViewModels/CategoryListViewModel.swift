import Foundation
import Combine
import CoreData

class CategoryListViewModel: ObservableObject {
    @Published var categories: [Category] = []
    
    private let dataService: DataService
    private var cancellables = Set<AnyCancellable>()

    init(dataService: DataService = DataServiceImpl()) {
        self.dataService = dataService
        loadCategories()
    }

    func loadCategories() {
        do {
            self.categories = try dataService.fetchCategories().sorted { $0.order < $1.order }
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
        
        let backgroundContext = dataService.newBackgroundContext()
        backgroundContext.performAndWait {
            let newCategory = Category(context: backgroundContext)
            newCategory.name = name
            newCategory.order = newOrder
            
            do {
                try backgroundContext.save()
                DispatchQueue.main.async {
                    self.loadCategories()
                }
            } catch {
                print("Error saving new category: \(error)")
            }
        }
    }

    func renameCategory(_ category: Category, newName: String) {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("New category name cannot be empty.")
            return
        }
        guard !categories.contains(where: { $0.objectID != category.objectID && $0.name == newName }) else {
            print("Another category with name '\(newName)' already exists.")
            return
        }

        guard let context = category.managedObjectContext else {
            print("Category has no context to save.")
            return
        }
        
        context.performAndWait {
            category.name = newName
            do {
                if context.hasChanges {
                    try context.save()
                }
                DispatchQueue.main.async {
                    self.loadCategories()
                }
            } catch {
                print("Error renaming category: \(error)")
            }
        }
    }
    
    func reorderCategories(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < categories.count,
              destinationIndex >= 0, destinationIndex <= categories.count else {
            print("Invalid source or destination index for reorder.")
            return
        }

        var reorderedCategories = categories
        let movedCategory = reorderedCategories.remove(at: sourceIndex)
        let actualDestinationIndex = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        reorderedCategories.insert(movedCategory, at: actualDestinationIndex)

        let backgroundContext = dataService.newBackgroundContext()
        backgroundContext.performAndWait {
            for (index, catMOID) in reorderedCategories.map({ $0.objectID }).enumerated() {
                if let categoryInContext = backgroundContext.object(with: catMOID) as? Category {
                    categoryInContext.order = Int16(index)
                }
            }
            do {
                try backgroundContext.save()
                DispatchQueue.main.async {
                    self.loadCategories() 
                }
            } catch {
                print("Error saving reordered categories: \(error)")
            }
        }
    }

    func deleteCategory(_ category: Category) {
        do {
            try dataService.delete(categories: [category])
            loadCategories() 
        } catch {
            print("Error deleting category: \(error)")
        }
    }
}