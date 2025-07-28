import SwiftUI
import CoreData

struct CategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewContext: NSManagedObjectContext
    let category: NSManagedObject? // nil for add mode, existing for edit
    let existingCategories: [NSManagedObject]
    
    @State private var name: String
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool
    
    private var isEditMode: Bool { category != nil }
    private var sheetTitle: String { isEditMode ? "Edit Category" : "Add Category" }
    
    init(viewContext: NSManagedObjectContext, category: NSManagedObject?, existingCategories: [NSManagedObject]) {
        self.viewContext = viewContext
        self.category = category
        self.existingCategories = existingCategories
        
        if let category = category {
            _name = State(initialValue: category.categoryName)
        } else {
            _name = State(initialValue: "")
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(sheetTitle)
                    .font(.title2)
                    .fontWeight(.medium)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            // Content
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Category Name")
                        .fontWeight(.medium)
                    TextField("e.g., Work, Personal", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($isFocused)
                }
                
                if let errorMessage = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .font(.subheadline)
                        Spacer()
                    }
                }
                
                Spacer()
            }
            .padding(20)
            
            Divider()
            
            // Footer
            HStack {
                if isEditMode {
                    Button("Delete", role: .destructive, action: deleteCategory)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isEditMode ? "Save" : "Add", action: saveCategory)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 400, height: 250)
        .onAppear {
            isFocused = true
        }
    }
    
    private func saveCategory() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Category name cannot be empty."
            return
        }
        
        // Check for duplicates
        let isDuplicate = existingCategories.contains { cat in
            let isSameObject = (cat.objectID == category?.objectID)
            let isSameName = cat.categoryName.lowercased() == trimmedName.lowercased()
            return isSameName && !isSameObject
        }
        
        if isDuplicate {
            errorMessage = "A category with this name already exists."
            return
        }
        
        do {
            if let category = category {
                // Edit mode
                category.setValue(trimmedName, forKey: "name")
            } else {
                // Add mode
                _ = viewContext.createCategory(name: trimmedName)
            }
            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to save category: \(error.localizedDescription)"
        }
    }
    
    private func deleteCategory() {
        guard let category = category else { return }
        
        let alert = NSAlert()
        alert.messageText = "Delete Category"
        alert.informativeText = "Are you sure you want to delete the '\(category.categoryName)' category? All prompts within it will also be deleted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            viewContext.delete(category)
            do {
                try viewContext.save()
                dismiss()
            } catch {
                errorMessage = "Failed to delete category: \(error.localizedDescription)"
            }
        }
    }
}