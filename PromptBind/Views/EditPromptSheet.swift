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
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case trigger, expansion
    }
    
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
        VStack(spacing: 0) {
            // Simple header
            HStack {
                Text("Edit Prompt")
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
            VStack(spacing: 24) {
                // Bind field (formerly trigger)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Bind")
                            .fontWeight(.medium)
                        Spacer()
                        Text("What you type")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    TextField("e.g., addr", text: $trigger)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .trigger)
                        .onSubmit { focusedField = .expansion }
                }
                
                // Prompt field (formerly expansion) - made much bigger
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Prompt")
                            .fontWeight(.medium)
                        Spacer()
                        Text("What it becomes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    TextEditor(text: $expansion)
                        .focused($focusedField, equals: .expansion)
                        .frame(minHeight: 200)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(.separatorColor), lineWidth: 1)
                        )
                        .font(.body)
                }
                
                // Settings row
                VStack(spacing: 12) {
                    HStack {
                        Text("Enabled")
                            .fontWeight(.medium)
                        Spacer()
                        Toggle("", isOn: $enabled)
                            .toggleStyle(.switch) // Use proper macOS toggle switch
                            .labelsHidden()
                    }
                    
                    HStack {
                        Text("Category")
                            .fontWeight(.medium)
                        Spacer()
                        
                        Picker("", selection: $selectedCategoryID) { // Remove duplicate "Category" label
                            Text("None").tag(nil as NSManagedObjectID?)
                            ForEach(categories, id: \.objectID) { category in
                                Text(category.categoryName).tag(category.objectID as NSManagedObjectID?)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(minWidth: 200)
                        .labelsHidden() // Hide the picker's built-in label
                    }
                }
                
                // Error message
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
                Button("Delete") {
                    deletePrompt()
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
                .disabled(trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || 
                         expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                         isSubmitting)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(20)
        }
        .frame(width: 450, height: 600) // Made much taller: 600 instead of 480
        .onAppear {
            focusedField = .trigger
        }
    }
    
    // MARK: - Actions
    private func deletePrompt() {
        let alert = NSAlert()
        alert.messageText = "Delete Prompt"
        alert.informativeText = "Are you sure you want to delete '\(trigger)'?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            do {
                viewContext.delete(prompt)
                try viewContext.save()
                dismiss()
            } catch {
                errorMessage = "Failed to delete prompt: \(error.localizedDescription)"
            }
        }
    }
    
    private func saveChanges() {
        errorMessage = nil
        isSubmitting = true
        
        let trimmedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExpansion = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validation
        guard !trimmedTrigger.isEmpty else {
            errorMessage = "Bind cannot be empty"
            isSubmitting = false
            return
        }
        
        guard !trimmedExpansion.isEmpty else {
            errorMessage = "Prompt cannot be empty"
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
                    errorMessage = "A prompt with bind '\(trimmedTrigger)' already exists"
                    isSubmitting = false
                    return
                }
            } catch {
                errorMessage = "Error checking for duplicate binds: \(error.localizedDescription)"
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