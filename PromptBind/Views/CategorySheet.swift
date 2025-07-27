import SwiftUI
import CoreData

struct AddCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewContext: NSManagedObjectContext
    let existingCategories: [NSManagedObject]
    
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Category Details")) {
                    TextField("Category Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .help("Enter a name for the new category")
                }
                
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addCategory()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
        }
        .frame(minWidth: 350, minHeight: 200)
    }
    
    private func addCategory() {
        errorMessage = nil
        isSubmitting = true
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validation
        guard !trimmedName.isEmpty else {
            errorMessage = "Category name cannot be empty"
            isSubmitting = false
            return
        }
        
        // Check for duplicate name
        if existingCategories.contains(where: { $0.categoryName.lowercased() == trimmedName.lowercased() }) {
            errorMessage = "A category with this name already exists"
            isSubmitting = false
            return
        }
        
        // Create the category
        do {
            let maxOrder = existingCategories.map { $0.categoryOrder }.max() ?? -1
            let newCategory = viewContext.createCategory(
                name: trimmedName,
                order: maxOrder + 1
            )
            
            try viewContext.save()
            print("AddCategorySheet: Successfully added category: \(trimmedName)")
            dismiss()
        } catch {
            print("AddCategorySheet: Error saving category: \(error)")
            errorMessage = "Failed to save category: \(error.localizedDescription)"
            isSubmitting = false
        }
    }
}

struct EditCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewContext: NSManagedObjectContext
    let category: NSManagedObject
    let existingCategories: [NSManagedObject]
    
    @State private var name: String
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var showingDeleteConfirmation = false
    
    init(viewContext: NSManagedObjectContext, category: NSManagedObject, existingCategories: [NSManagedObject]) {
        self.viewContext = viewContext
        self.category = category
        self.existingCategories = existingCategories
        self._name = State(initialValue: category.categoryName)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Category")
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
            
            // Main content
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Category Name")
                        .fontWeight(.medium)
                    
                    TextField("Enter category name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                
                if let errorMessage = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(20)
            
            Divider()
            
            // Footer buttons
            HStack {
                Button("Delete Category") {
                    showingDeleteConfirmation = true
                }
                .foregroundColor(.red)
                .buttonStyle(.plain)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button(action: saveChanges) {
                    if isSubmitting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Saving...")
                        }
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(20)
        }
        .frame(width: 400, height: 300)
        .alert("Delete Category", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteCategory()
            }
        } message: {
            Text("Are you sure you want to delete '\(category.categoryName)'?\n\nAll prompts in this category will be moved to 'Uncategorized'.")
        }
    }
    
    private func saveChanges() {
        errorMessage = nil
        isSubmitting = true
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validation
        guard !trimmedName.isEmpty else {
            errorMessage = "Category name cannot be empty"
            isSubmitting = false
            return
        }
        
        // Check for duplicate name (excluding current category)
        if trimmedName.lowercased() != category.categoryName.lowercased() {
            if existingCategories.contains(where: { $0.categoryName.lowercased() == trimmedName.lowercased() && $0.objectID != category.objectID }) {
                errorMessage = "A category with this name already exists"
                isSubmitting = false
                return
            }
        }
        
        // Update the category
        do {
            category.categoryName = trimmedName
            try viewContext.save()
            print("EditCategorySheet: Successfully updated category: \(trimmedName)")
            dismiss()
        } catch {
            print("EditCategorySheet: Error saving category: \(error)")
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
            isSubmitting = false
        }
    }
    
    private func deleteCategory() {
        do {
            // Move all prompts in this category to uncategorized
            let prompts = category.categoryPrompts
            for prompt in prompts {
                prompt.promptCategory = nil
            }
            
            // Delete the category
            viewContext.delete(category)
            try viewContext.save()
            
            print("EditCategorySheet: Successfully deleted category")
            dismiss()
        } catch {
            errorMessage = "Failed to delete category: \(error.localizedDescription)"
        }
    }
}