import Foundation
import SwiftData
import AppKit

class DataExportImportService {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Export Functions
    
    func exportAllData() -> ExportData {
        let categories = fetchAllCategories()
        let prompts = fetchAllPrompts()
        
        let exportCategories = categories.map { ExportCategory(from: $0) }
        let exportPrompts = prompts.map { ExportPrompt(from: $0) }
        
        return ExportData(categories: exportCategories, prompts: exportPrompts)
    }
    
    func exportDataToJSONFile() -> URL? {
        let exportData = exportAllData()
        
        guard let jsonData = try? JSONEncoder().encode(exportData) else {
            print("Failed to encode export data to JSON")
            return nil
        }
        
        let savePanel = NSSavePanel()
        savePanel.title = "Export PromptBind Data"
        savePanel.nameFieldStringValue = "PromptBind_Export_\(dateString()).json"
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        
        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return nil
        }
        
        do {
            try jsonData.write(to: url)
            return url
        } catch {
            print("Failed to write export file: \(error)")
            return nil
        }
    }
    
    // MARK: - Import Functions
    
    func importDataFromJSONFile() -> ImportResult {
        let openPanel = NSOpenPanel()
        openPanel.title = "Import PromptBind Data"
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        
        guard openPanel.runModal() == .OK, let url = openPanel.urls.first else {
            return .failure(error: .fileReadError)
        }
        
        do {
            let jsonData = try Data(contentsOf: url)
            return importDataFromJSON(data: jsonData)
        } catch {
            print("Failed to read import file: \(error)")
            return .failure(error: .fileReadError)
        }
    }
    
    func importDataFromJSON(data: Data) -> ImportResult {
        do {
            let exportData = try JSONDecoder().decode(ExportData.self, from: data)
            return processImportData(data: exportData)
        } catch {
            print("Failed to decode JSON: \(error)")
            return .failure(error: .invalidJSON)
        }
    }
    
    func processImportData(data: ExportData) -> ImportResult {
        // Validate schema version
        guard data.schemaVersion == "1.0" else {
            return .failure(error: .unsupportedSchemaVersion)
        }
        
        var categoriesAdded = 0
        var promptsAdded = 0
        
        do {
            // Import categories first
            var categoryMap: [String: Category] = [:]
            
            for exportCategory in data.categories {
                // Check if category with this name already exists
                let descriptor = FetchDescriptor<Category>(predicate: #Predicate<Category> { $0.name == exportCategory.name })
                let existingCategories = try modelContext.fetch(descriptor)
                
                if let existingCategory = existingCategories.first {
                    // Use existing category
                    categoryMap[exportCategory.id] = existingCategory
                } else {
                    // Create new category
                    let newCategory = Category(name: exportCategory.name, order: Int16(exportCategory.order))
                    modelContext.insert(newCategory)
                    categoryMap[exportCategory.id] = newCategory
                    categoriesAdded += 1
                }
            }
            
            // Import prompts
            for exportPrompt in data.prompts {
                // Check if prompt with this trigger already exists (skip duplicates)
                let descriptor = FetchDescriptor<Prompt>(predicate: #Predicate<Prompt> { $0.trigger == exportPrompt.trigger })
                let existingPrompts = try modelContext.fetch(descriptor)
                
                if existingPrompts.isEmpty {
                    // Create new prompt
                    let newPrompt = Prompt(trigger: exportPrompt.trigger, 
                                         expansion: exportPrompt.expansion, 
                                         enabled: exportPrompt.enabled)
                    
                    // Assign category if available
                    if let categoryId = exportPrompt.categoryId,
                       let category = categoryMap[categoryId] {
                        newPrompt.category = category
                    }
                    
                    modelContext.insert(newPrompt)
                    promptsAdded += 1
                } else {
                    print("Skipping duplicate prompt with trigger: \(exportPrompt.trigger)")
                }
            }
            
            // Save all changes
            try modelContext.save()
            
            return .success(categoriesAdded: categoriesAdded, promptsAdded: promptsAdded)
            
        } catch {
            print("Database error during import: \(error)")
            return .failure(error: .databaseError(error.localizedDescription))
        }
    }
    
    // MARK: - Helper Functions
    
    private func fetchAllCategories() -> [Category] {
        do {
            let descriptor = FetchDescriptor<Category>(sortBy: [SortDescriptor(\.order)])
            return try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching categories: \(error)")
            return []
        }
    }
    
    private func fetchAllPrompts() -> [Prompt] {
        do {
            let descriptor = FetchDescriptor<Prompt>(sortBy: [SortDescriptor(\.trigger)])
            return try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching prompts: \(error)")
            return []
        }
    }
    
    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
}