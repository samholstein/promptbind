import Foundation

enum CategorySelection: Hashable {
    case all
    case category(Category)
    
    var displayName: String {
        switch self {
        case .all:
            return "All"
        case .category(let category):
            return category.name
        }
    }
    
    var isAll: Bool {
        switch self {
        case .all:
            return true
        case .category:
            return false
        }
    }
    
    var category: Category? {
        switch self {
        case .all:
            return nil
        case .category(let category):
            return category
        }
    }
}