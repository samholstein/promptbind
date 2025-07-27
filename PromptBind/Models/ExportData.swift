import Foundation

// MARK: - Export/Import Data Models

struct ExportData: Codable {
    let version: String
    let exportDate: Date
    let categories: [ExportCategory]
    let prompts: [ExportPrompt]
    
    init(version: String = "1.0", categories: [ExportCategory] = [], prompts: [ExportPrompt] = []) {
        self.version = version
        self.exportDate = Date()
        self.categories = categories
        self.prompts = prompts
    }
}

struct ExportCategory: Codable, Identifiable {
    let id: String
    let name: String
    let order: Int
    
    init(id: String = UUID().uuidString, name: String, order: Int = 0) {
        self.id = id
        self.name = name
        self.order = order
    }
}

struct ExportPrompt: Codable, Identifiable {
    let id: String
    let trigger: String
    let prompt: String
    let enabled: Bool
    let categoryId: String?
    
    init(id: String = UUID().uuidString, trigger: String, prompt: String, enabled: Bool = true, categoryId: String? = nil) {
        self.id = id
        self.trigger = trigger
        self.prompt = prompt
        self.enabled = enabled
        self.categoryId = categoryId
    }
}

// MARK: - Error Handling

enum ImportExportError: LocalizedError {
    case fileNotFound
    case invalidJSON
    case coreDataError(Error)
    case unknownVersion(String)
    case duplicateTrigger(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "File not found"
        case .invalidJSON:
            return "Invalid JSON format"
        case .coreDataError(let error):
            return "Database error: \(error.localizedDescription)"
        case .unknownVersion(let version):
            return "Unsupported file version: \(version)"
        case .duplicateTrigger(let trigger):
            return "Duplicate trigger found: \(trigger)"
        }
    }
}