import Foundation
import CoreData // For interacting with DataService

// --- Codable Structs for Import/Export ---

struct ExportablePromptItem: Codable {
    let id: UUID
    let trigger: String
    let content: String
    let categoryName: String // Using name for simplicity in export/import
}

struct ExportableCategory: Codable {
    let name: String
    let order: Int16 // Keep order if possible
    // Prompts will be linked via categoryName in ExportablePromptItem
}

// Wrapper for the whole library export
struct ExportableLibrary: Codable {
    let schemaVersion: String = "1.0" // Current schema version
    let categories: [ExportableCategory]
    let prompts: [ExportablePromptItem]
}

// --- Merge Strategies Enum ---

enum ImportStrategy: String, CaseIterable, Identifiable {
    case merge // Add new, update existing (based on trigger/name), keep others
    case overwrite // Delete all existing data and replace with imported data
    case skipDuplicates // Add new, skip if trigger/name already exists

    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .merge: return "Merge with Existing"
        case .overwrite: return "Overwrite Existing Library"
        case .skipDuplicates: return "Add New, Skip Duplicates"
        }
    }
}

// --- Import/Export Service Protocol (Optional but good practice) ---

protocol ImportExportServiceProtocol {
    // JSON
    func exportToJSON(dataService: DataService) throws -> Data
    func importFromJSON(data: Data, strategy: ImportStrategy, dataService: DataService) throws
    
    // CSV (might be simpler, e.g., only prompts, or specific format)
    // func exportToCSV(dataService: DataService) throws -> Data
    // func importFromCSV(data: Data, strategy: ImportStrategy, dataService: DataService) throws // CSV import is more complex with strategies
}

// --- Import/Export Service Implementation ---

class ImportExportServiceImpl: ImportExportServiceProtocol {

    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    init() {
        jsonEncoder.outputFormatting = .prettyPrinted // For readable JSON
    }

    // MARK: - JSON Export
    func exportToJSON(dataService: DataService) throws -> Data {
        let prompts = try dataService.fetchPrompts()
        let categories = try dataService.fetchCategories()

        let exportablePrompts = prompts.map { prompt in
            ExportablePromptItem(
                id: prompt.id ?? UUID(), // Ensure ID exists
                trigger: prompt.trigger ?? "",
                content: prompt.content ?? "",
                categoryName: prompt.category?.name ?? "Uncategorized" // Default if category is nil
            )
        }

        let exportableCategories = categories.map { category in
            ExportableCategory(
                name: category.name ?? "",
                order: category.order
            )
        }

        let library = ExportableLibrary(categories: exportableCategories, prompts: exportablePrompts)
        return try jsonEncoder.encode(library)
    }

    // MARK: - JSON Import
    func importFromJSON(data: Data, strategy: ImportStrategy, dataService: DataService) throws {
        let library = try jsonDecoder.decode(ExportableLibrary.self, from: data)

        // TODO: Validate schemaVersion if necessary. For v1.0, we might not need complex migration.
        // if library.schemaVersion != "1.0" {
        //     throw ImportError.invalidSchemaVersion
        // }

        let backgroundContext = dataService.newBackgroundContext()

        try backgroundContext.performAndWait { // Perform Core Data operations synchronously on the context's queue
            var existingPrompts = try dataService.fetchPrompts(context: backgroundContext)
            var existingCategories = try dataService.fetchCategories(context: backgroundContext)

            if strategy == .overwrite {
                for prompt in existingPrompts { backgroundContext.delete(prompt) }
                for category in existingCategories { backgroundContext.delete(category) }
                // After deleting, clear the local arrays as well
                existingPrompts = []
                existingCategories = []
                // Note: DataService delete methods might save immediately.
                // For overwrite, it's better to delete then save once after new items are added.
                // This current implementation will work if backgroundContext.save() is called at the end.
            }

            var categoriesToSaveByName: [String: Category] = [:]
            // Pre-populate with existing categories for quick lookup
            for cat in existingCategories {
                if let name = cat.name { categoriesToSaveByName[name] = cat }
            }


            // Process Categories
            for exportableCategory in library.categories {
                var category: Category?

                if let existingCat = existingCategories.first(where: { $0.name == exportableCategory.name }) {
                    if strategy == .overwrite || strategy == .merge {
                        category = existingCat
                        category?.order = exportableCategory.order // Update order in merge
                    } else if strategy == .skipDuplicates {
                        category = existingCat // Keep existing if skipping
                    }
                } else { // New category
                    category = Category(context: backgroundContext)
                    category?.name = exportableCategory.name
                    category?.order = exportableCategory.order
                }
                if let cat = category, let name = cat.name {
                    categoriesToSaveByName[name] = cat
                }
            }

            // Process Prompts
            for exportablePrompt in library.prompts {
                var prompt: PromptItem?

                if let existingPrompt = existingPrompts.first(where: { $0.trigger == exportablePrompt.trigger }) {
                    switch strategy {
                    case .overwrite, .merge:
                        prompt = existingPrompt
                        prompt?.content = exportablePrompt.content
                        if let cat = categoriesToSaveByName[exportablePrompt.categoryName] {
                            prompt?.category = cat
                        } else { 
                            let newCat = Category(context: backgroundContext)
                            newCat.name = exportablePrompt.categoryName
                            newCat.order = (categoriesToSaveByName.values.map { $0.order }.max() ?? -1) + 1
                            categoriesToSaveByName[exportablePrompt.categoryName] = newCat
                            prompt?.category = newCat
                        }
                        prompt?.id = exportablePrompt.id 
                    case .skipDuplicates:
                        continue // Skip this prompt
                    }
                } else { // New prompt
                    prompt = PromptItem(context: backgroundContext)
                    prompt?.id = exportablePrompt.id
                    prompt?.trigger = exportablePrompt.trigger
                    prompt?.content = exportablePrompt.content
                    if let cat = categoriesToSaveByName[exportablePrompt.categoryName] {
                        prompt?.category = cat
                    } else {
                        let newCat = Category(context: backgroundContext)
                        newCat.name = exportablePrompt.categoryName
                        newCat.order = (categoriesToSaveByName.values.map { $0.order }.max() ?? -1) + 1
                        categoriesToSaveByName[exportablePrompt.categoryName] = newCat
                        prompt?.category = newCat
                    }
                }
            }
            
            try backgroundContext.save()
        }
    }
}

// DataService extension methods are already in DataService.swift.
// No need to repeat them here if that file is correctly restored.

enum ImportError: Error {
    case invalidSchemaVersion
    case dataDecodingError(Error)
    // Add other specific import errors as needed
}