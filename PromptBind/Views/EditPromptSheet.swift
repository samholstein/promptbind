import SwiftUI
import CoreData

struct EditPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewContext: NSManagedObjectContext
    let prompt: NSManagedObject
    let categories: [NSManagedObject]
    
    @State private var trigger: String
    @State private var expansion: String
    @State private var enabled: Bool
    @State private var selectedCategoryID: NSManagedObjectID?
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    
    init(viewContext: NSManagedObjectContext, prompt: NSManagedObject, categories: [NSManagedObject]) {
        self.viewContext = viewContext
        self.prompt = prompt
        self.categories = categories
        
        // Initialize state with current prompt values
        self._trigger = State(initialValue: prompt.promptTrigger)
        self._expansion = State(initialValue: prompt.promptExpansion)
        self._enabled = State(initialValue: prompt.promptEnabled)
        self._selectedCategoryID = State(initialValue: prompt.promptCategory?.objectID)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Prompt Details")) {
                    TextField("Trigger", text: $trigger)
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
            .navigationTitle("Edit Prompt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || 
                             expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                             isSubmitting)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
    
    private func saveChanges() {
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
        
        // Check for duplicate trigger (excluding current prompt)
        if trimmedTrigger != prompt.promptTrigger {
            let request = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
            request.predicate = NSPredicate(format: "trigger == %@ AND SELF != %@", trimmedTrigger, prompt)
            
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
        }
        
        // Find the selected category
        var categoryToUse: NSManagedObject?
        if let categoryID = selectedCategoryID {
            categoryToUse = categories.first { $0.objectID == categoryID }
        }
        
        // Update the prompt
        do {
            prompt.promptTrigger = trimmedTrigger
            prompt.promptExpansion = trimmedExpansion
            prompt.promptEnabled = enabled
            prompt.promptCategory = categoryToUse
            
            try viewContext.save()
            print("EditPromptSheet: Successfully updated prompt: \(trimmedTrigger)")
            dismiss()
        } catch {
            print("EditPromptSheet: Error saving prompt: \(error)")
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
            isSubmitting = false
        }
    }
}

struct EditPromptSheet_Previews: PreviewProvider {
    static var previews: some View {
        let context = CoreDataStack.shared.viewContext
        let category = context.createCategory(name: "Test Category")
        let prompt = context.createPrompt(trigger: "test", expansion: "This is a test", category: category)
        
        return EditPromptSheet(
            viewContext: context,
            prompt: prompt,
            categories: [category]
        )
    }
}