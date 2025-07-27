import SwiftUI
import CoreData

struct AddPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewContext: NSManagedObjectContext
    let selectedCategory: NSManagedObject?
    let categories: [NSManagedObject]
    
    @State private var trigger = ""
    @State private var expansion = ""
    @State private var enabled = true
    @State private var selectedCategoryID: NSManagedObjectID?
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    
    init(viewContext: NSManagedObjectContext, selectedCategory: NSManagedObject?, categories: [NSManagedObject]) {
        self.viewContext = viewContext
        self.selectedCategory = selectedCategory
        self.categories = categories
        self._selectedCategoryID = State(initialValue: selectedCategory?.objectID)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Prompt Details")) {
                    TextField("Trigger (e.g., 'addr')", text: $trigger)
                        .textFieldStyle(.roundedBorder)
                        .help("The text you type that will be replaced")
                    
                    TextField("Expansion", text: $expansion, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                        .help("The text that will replace the trigger")
                }
                
                Section(header: Text("Settings")) {
                    Toggle("Enabled", isOn: $enabled)
                        .help("Whether this prompt is active")
                    
                    Picker("Category", selection: $selectedCategoryID) {
                        Text("No Category").tag(nil as NSManagedObjectID?)
                        ForEach(categories, id: \.objectID) { category in
                            Text(category.categoryName).tag(category.objectID as NSManagedObjectID?)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Prompt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addPrompt()
                    }
                    .disabled(trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || 
                             expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                             isSubmitting)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
    
    private func addPrompt() {
        errorMessage = nil
        isSubmitting = true
        
        let trimmedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExpansion = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validation
        guard !trimmedTrigger.isEmpty else {
            errorMessage = "Trigger cannot be empty"
            isSubmitting = false
            return
        }
        
        guard !trimmedExpansion.isEmpty else {
            errorMessage = "Expansion cannot be empty"
            isSubmitting = false
            return
        }
        
        // Check for duplicate trigger
        let request = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
        request.predicate = NSPredicate(format: "trigger == %@", trimmedTrigger)
        
        do {
            let existingPrompts = try viewContext.fetch(request)
            if !existingPrompts.isEmpty {
                errorMessage = "A prompt with trigger '\(trimmedTrigger)' already exists"
                isSubmitting = false
                return
            }
        } catch {
            errorMessage = "Error checking for duplicate triggers: \(error.localizedDescription)"
            isSubmitting = false
            return
        }
        
        // Find the selected category
        var categoryToUse: NSManagedObject?
        if let categoryID = selectedCategoryID {
            categoryToUse = categories.first { $0.objectID == categoryID }
        }
        
        // Create the prompt
        do {
            let newPrompt = viewContext.createPrompt(
                trigger: trimmedTrigger,
                expansion: trimmedExpansion,
                enabled: enabled,
                category: categoryToUse
            )
            
            try viewContext.save()
            print("AddPromptSheet: Successfully added prompt: \(trimmedTrigger)")
            dismiss()
        } catch {
            print("AddPromptSheet: Error saving prompt: \(error)")
            errorMessage = "Failed to save prompt: \(error.localizedDescription)"
            isSubmitting = false
        }
    }
}

struct AddPromptSheet_Previews: PreviewProvider {
    static var previews: some View {
        let context = CoreDataStack.shared.viewContext
        let category = context.createCategory(name: "Test Category")
        
        return AddPromptSheet(
            viewContext: context,
            selectedCategory: category,
            categories: [category]
        )
    }
}