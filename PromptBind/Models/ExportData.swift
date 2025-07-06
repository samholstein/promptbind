import Foundation

struct ExportData: Codable {
    let schemaVersion: String
    let exportDate: String
    let appVersion: String
    let categories: [ExportCategory]
    let prompts: [ExportPrompt]
    
    init(categories: [ExportCategory], prompts: [ExportPrompt]) {
        self.schemaVersion = "1.0"
        self.exportDate = ISO8601DateFormatter().string(from: Date())
        self.appVersion = "1.0"
        self.categories = categories
        self.prompts = prompts
    }
}

struct ExportCategory: Codable {
    let id: String
    let name: String
    let order: Int
    
    init(from category: Category) {
        self.id = String(describing: category.id)
        self.name = category.name
        self.order = Int(category.order)
    }
}

struct ExportPrompt: Codable {
    let id: String
    let trigger: String
    let expansion: String
    let enabled: Bool
    let categoryId: String?
    
    init(from prompt: Prompt) {
        self.id = String(describing: prompt.id)
        self.trigger = prompt.trigger
        self.expansion = prompt.expansion
        self.enabled = prompt.enabled
        self.categoryId = prompt.category?.id != nil ? String(describing: prompt.category!.id) : nil
    }
}

enum ImportResult {
    case success(categoriesAdded: Int, promptsAdded: Int)
    case failure(error: ImportError)
}

enum ImportError: LocalizedError {
    case fileReadError
    case invalidJSON
    case unsupportedSchemaVersion
    case databaseError(String)
    
    var errorDescription: String? {
        switch self {
        case .fileReadError:
            return "Could not read the selected file."
        case .invalidJSON:
            return "The file does not contain valid JSON data."
        case .unsupportedSchemaVersion:
            return "This file was created with an unsupported version of PromptBind."
        case .databaseError(let message):
            return "Database error: \(message)"
        }
    }
}