import Foundation
import CoreData

protocol DataService {
    func fetchPrompts() throws -> [PromptItem]
    func fetchCategories() throws -> [Category]
    
    func saveContext() throws
    func delete(prompts: [PromptItem]) throws
    func delete(categories: [Category]) throws

    var viewContext: NSManagedObjectContext { get }
    func newBackgroundContext() -> NSManagedObjectContext

    // Extension methods defined in ImportExportService for fetching on specific context
    func fetchPrompts(context: NSManagedObjectContext) throws -> [PromptItem]
    func fetchCategories(context: NSManagedObjectContext) throws -> [Category]
}