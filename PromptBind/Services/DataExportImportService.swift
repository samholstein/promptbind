import Foundation
import CoreData
import AppKit

@MainActor
class DataExportImportService: ObservableObject {
    private let viewContext: NSManagedObjectContext
    
    @Published var isProcessing = false
    @Published var lastError: ImportExportError?
    @Published var successMessage: String?
    
    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
    }
    
    // MARK: - Export
    
    func exportData() {
        isProcessing = true
        lastError = nil
        successMessage = nil
        
        Task {
            do {
                let exportData = try await createExportData()
                let jsonData = try JSONEncoder().encode(exportData)
                
                // Show save dialog
                let savePanel = NSSavePanel()
                savePanel.title = "Export PromptBind Data"
                savePanel.nameFieldStringValue = "PromptBind-Export-\(DateFormatter.filenameDateFormatter.string(from: Date())).json"
                savePanel.allowedContentTypes = [.json]
                savePanel.canCreateDirectories = true
                
                if savePanel.runModal() == .OK, let url = savePanel.url {
                    try jsonData.write(to: url)
                    successMessage = "Successfully exported \(exportData.prompts.count) prompts to \(url.lastPathComponent)"
                }
            } catch {
                if let importExportError = error as? ImportExportError {
                    lastError = importExportError
                } else {
                    lastError = .coreDataError(error)
                }
            }
            isProcessing = false
        }
    }
    
    private func createExportData() async throws -> ExportData {
        // Fetch categories
        let categoryRequest = NSFetchRequest<NSManagedObject>(entityName: "Category")
        categoryRequest.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
        let categories = try viewContext.fetch(categoryRequest)
        
        // Fetch prompts
        let promptRequest = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
        promptRequest.sortDescriptors = [NSSortDescriptor(key: "trigger", ascending: true)]
        let prompts = try viewContext.fetch(promptRequest)
        
        // Convert to export format
        let exportCategories = categories.map { category in
            ExportCategory(
                id: category.categoryID.uuidString,
                name: category.categoryName,
                order: Int(category.categoryOrder)
            )
        }
        
        let exportPrompts = prompts.map { prompt in
            ExportPrompt(
                id: prompt.promptID.uuidString,
                trigger: prompt.promptTrigger,
                prompt: prompt.promptExpansion,
                enabled: prompt.promptEnabled,
                categoryId: prompt.promptCategory?.categoryID.uuidString
            )
        }
        
        return ExportData(categories: exportCategories, prompts: exportPrompts)
    }
    
    // MARK: - Import
    
    func importData() {
        isProcessing = true
        lastError = nil
        successMessage = nil
        
        Task {
            do {
                // Show open dialog
                let openPanel = NSOpenPanel()
                openPanel.title = "Import PromptBind Data"
                openPanel.allowedContentTypes = [.json]
                openPanel.allowsMultipleSelection = false
                
                if openPanel.runModal() == .OK, let url = openPanel.url {
                    let jsonData = try Data(contentsOf: url)
                    let importData = try JSONDecoder().decode(ExportData.self, from: jsonData)
                    
                    try await processImportData(importData)
                    successMessage = "Successfully imported \(importData.prompts.count) prompts from \(url.lastPathComponent)"
                }
            } catch {
                if let importExportError = error as? ImportExportError {
                    lastError = importExportError
                } else if error is DecodingError {
                    lastError = .invalidJSON
                } else {
                    lastError = .coreDataError(error)
                }
            }
            isProcessing = false
        }
    }
    
    private func processImportData(_ importData: ExportData) async throws {
        // Check for duplicate triggers before importing
        let existingTriggers = try getExistingTriggers()
        let duplicates = importData.prompts.compactMap { prompt in
            existingTriggers.contains(prompt.trigger) ? prompt.trigger : nil
        }
        
        if !duplicates.isEmpty {
            throw ImportExportError.duplicateTrigger(duplicates.joined(separator: ", "))
        }
        
        // Create category mapping
        var categoryMapping: [String: NSManagedObject] = [:]
        
        // Import categories
        for exportCategory in importData.categories {
            let category = viewContext.createCategory(
                name: exportCategory.name,
                order: Int16(exportCategory.order)
            )
            categoryMapping[exportCategory.id] = category
        }
        
        // Import prompts
        for exportPrompt in importData.prompts {
            let category = exportPrompt.categoryId.flatMap { categoryMapping[$0] }
            
            _ = viewContext.createPrompt(
                trigger: exportPrompt.trigger,
                expansion: exportPrompt.prompt,
                enabled: exportPrompt.enabled,
                category: category
            )
        }
        
        // Save to Core Data
        try viewContext.save()
    }
    
    private func getExistingTriggers() throws -> Set<String> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
        request.propertiesToFetch = ["trigger"]
        let prompts = try viewContext.fetch(request)
        return Set(prompts.map { $0.promptTrigger })
    }
    
    // MARK: - Default Prompts
    
    func loadDefaultPrompts() async throws -> ExportData {
        print("DataExportImportService: Looking for DefaultPrompts.json in bundle...")
        
        guard let url = Bundle.main.url(forResource: "DefaultPrompts", withExtension: "json") else {
            print("DataExportImportService: DefaultPrompts.json not found in bundle")
            throw ImportExportError.fileNotFound
        }
        
        print("DataExportImportService: Found DefaultPrompts.json at \(url.path)")
        
        let jsonData = try Data(contentsOf: url)
        print("DataExportImportService: Loaded JSON data, size: \(jsonData.count) bytes")
        
        let importData = try JSONDecoder().decode(ExportData.self, from: jsonData)
        print("DataExportImportService: Decoded \(importData.prompts.count) prompts from JSON")
        
        return importData
    }
    
    private func processDefaultImportData(_ importData: ExportData) async throws {
        print("DataExportImportService: Processing default import data...")
        
        // Don't check for duplicates when loading defaults - we want to load them fresh
        
        // Create category mapping
        var categoryMapping: [String: NSManagedObject] = [:]
        
        // Import categories
        for exportCategory in importData.categories {
            print("DataExportImportService: Creating category: \(exportCategory.name)")
            let category = viewContext.createCategory(
                name: exportCategory.name,
                order: Int16(exportCategory.order)
            )
            categoryMapping[exportCategory.id] = category
        }
        
        // Import prompts
        for exportPrompt in importData.prompts {
            print("DataExportImportService: Creating prompt: \(exportPrompt.trigger)")
            let category = exportPrompt.categoryId.flatMap { categoryMapping[$0] }
            
            _ = viewContext.createPrompt(
                trigger: exportPrompt.trigger,
                expansion: exportPrompt.prompt,
                enabled: exportPrompt.enabled,
                category: category
            )
        }
        
        // Save to Core Data
        try viewContext.save()
        print("DataExportImportService: Successfully saved \(importData.prompts.count) default prompts")
    }
}

// MARK: - Date Formatter Extension

extension DateFormatter {
    static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()
}