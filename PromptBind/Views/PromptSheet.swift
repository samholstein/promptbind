import SwiftUI
import CoreData

struct PromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    let viewContext: NSManagedObjectContext
    let prompt: NSManagedObject? // nil for add mode, existing prompt for edit mode
    let selectedCategory: NSManagedObject?
    let categories: [NSManagedObject]
    
    @State private var trigger: String
    @State private var expansion: String
    @State private var enabled: Bool
    @State private var selectedCategoryID: NSManagedObjectID?
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var showingUpgradePrompt = false
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case trigger, expansion
    }
    
    // Computed properties for mode detection
    private var isEditMode: Bool { prompt != nil }
    private var sheetTitle: String { isEditMode ? "Edit Prompt" : "Add Prompt" }
    private var saveButtonTitle: String { isEditMode ? "Save" : "Add" }
    
    init(viewContext: NSManagedObjectContext, prompt: NSManagedObject? = nil, selectedCategory: NSManagedObject? = nil, categories: [NSManagedObject]) {
        self.viewContext = viewContext
        self.prompt = prompt
        self.selectedCategory = selectedCategory
        self.categories = categories
        
        if let existingPrompt = prompt {
            // Edit mode: initialize with existing prompt values
            self._trigger = State(initialValue: existingPrompt.promptTrigger)
            self._expansion = State(initialValue: existingPrompt.promptExpansion)
            self._enabled = State(initialValue: existingPrompt.promptEnabled)
            self._selectedCategoryID = State(initialValue: existingPrompt.promptCategory?.objectID)
        } else {
            // Add mode: initialize with defaults
            self._trigger = State(initialValue: "")
            self._expansion = State(initialValue: "")
            self._enabled = State(initialValue: true)
            self._selectedCategoryID = State(initialValue: selectedCategory?.objectID)
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
            
            // Main content
            VStack(spacing: 24) {
                // Free tier limit warning (only show in add mode for free users)
                if !isEditMode && !subscriptionManager.canCreatePrompt() {
                    freeTierLimitView
                }
                
                // Bind field (trigger)
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
                        .disabled(!isEditMode && !subscriptionManager.canCreatePrompt())
                }
                
                // Prompt field (expansion)
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
                        .disabled(!isEditMode && !subscriptionManager.canCreatePrompt())
                }
                
                // Settings row
                VStack(spacing: 12) {
                    HStack {
                        Text("Enabled")
                            .fontWeight(.medium)
                        Spacer()
                        Toggle("", isOn: $enabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(!isEditMode && !subscriptionManager.canCreatePrompt())
                    }
                    
                    HStack {
                        Text("Category")
                            .fontWeight(.medium)
                        Spacer()
                        
                        Picker("", selection: $selectedCategoryID) {
                            Text("None").tag(nil as NSManagedObjectID?)
                            ForEach(categories, id: \.objectID) { category in
                                Text(category.categoryName).tag(category.objectID as NSManagedObjectID?)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(minWidth: 200)
                        .labelsHidden()
                        .disabled(!isEditMode && !subscriptionManager.canCreatePrompt())
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
                // Delete button (only in edit mode)
                if isEditMode {
                    Button("Delete") {
                        deletePrompt()
                    }
                    .foregroundColor(.red)
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                if !isEditMode && !subscriptionManager.canCreatePrompt() {
                    Button("Upgrade to Pro") {
                        showingUpgradePrompt = true
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                } else {
                    Button(action: savePrompt) {
                        if isSubmitting {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Saving...")
                            }
                        } else {
                            Text(saveButtonTitle)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || 
                             expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                             isSubmitting)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(20)
        }
        .frame(width: 450, height: 600)
        .onAppear {
            if isEditMode || subscriptionManager.canCreatePrompt() {
                focusedField = .trigger
            }
        }
        .sheet(isPresented: $showingUpgradePrompt) {
            UpgradePromptView()
        }
    }
    
    // MARK: - Subscription UI
    
    private var freeTierLimitView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.orange)
                Text("Free Tier Limit Reached")
                    .fontWeight(.semibold)
                Spacer()
            }
            
            Text("You've reached the 5-prompt limit for free accounts. Upgrade to Pro for unlimited prompts and advanced features.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current: \(subscriptionManager.promptCount)/5 prompts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Pro: Unlimited prompts")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Actions
    private func deletePrompt() {
        guard let prompt = prompt else { return }
        
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
    
    private func savePrompt() {
        // In add mode, check subscription limits before saving
        if !isEditMode && !subscriptionManager.canCreatePrompt() {
            showingUpgradePrompt = true
            return
        }
        
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
        
        // Check for duplicate trigger
        if isEditMode {
            // Edit mode: exclude current prompt from duplicate check
            if let currentPrompt = prompt, trimmedTrigger != currentPrompt.promptTrigger {
                if let duplicateError = checkForDuplicateTrigger(trimmedTrigger, excluding: currentPrompt) {
                    errorMessage = duplicateError
                    isSubmitting = false
                    return
                }
            }
        } else {
            // Add mode: check all prompts for duplicates
            if let duplicateError = checkForDuplicateTrigger(trimmedTrigger, excluding: nil) {
                errorMessage = duplicateError
                isSubmitting = false
                return
            }
        }
        
        // Find the selected category
        var categoryToUse: NSManagedObject?
        if let categoryID = selectedCategoryID {
            categoryToUse = categories.first { $0.objectID == categoryID }
        }
        
        do {
            if isEditMode {
                // Update existing prompt
                guard let existingPrompt = prompt else { return }
                existingPrompt.promptTrigger = trimmedTrigger
                existingPrompt.promptExpansion = trimmedExpansion
                existingPrompt.promptEnabled = enabled
                existingPrompt.promptCategory = categoryToUse
                print("PromptSheet: Successfully updated prompt: \(trimmedTrigger)")
            } else {
                // Create new prompt
                _ = viewContext.createPrompt(
                    trigger: trimmedTrigger,
                    expansion: trimmedExpansion,
                    enabled: enabled,
                    category: categoryToUse
                )
                print("PromptSheet: Successfully added prompt: \(trimmedTrigger)")
            }
            
            try viewContext.save()
            dismiss()
        } catch {
            print("PromptSheet: Error saving prompt: \(error)")
            errorMessage = "Failed to save prompt: \(error.localizedDescription)"
            isSubmitting = false
        }
    }
    
    private func checkForDuplicateTrigger(_ trigger: String, excluding excludedPrompt: NSManagedObject?) -> String? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
        
        if let excludedPrompt = excludedPrompt {
            request.predicate = NSPredicate(format: "trigger == %@ AND SELF != %@", trigger, excludedPrompt)
        } else {
            request.predicate = NSPredicate(format: "trigger == %@", trigger)
        }
        
        do {
            let existingPrompts = try viewContext.fetch(request)
            if !existingPrompts.isEmpty {
                return "A prompt with bind '\(trigger)' already exists"
            }
        } catch {
            return "Error checking for duplicate binds: \(error.localizedDescription)"
        }
        
        return nil
    }
}

struct PromptSheet_Previews: PreviewProvider {
    static var previews: some View {
        let context = CoreDataStack.shared.viewContext
        let category = context.createCategory(name: "Test Category")
        let prompt = context.createPrompt(trigger: "test", expansion: "This is a test", category: category)
        
        Group {
            // Add mode preview
            PromptSheet(
                viewContext: context,
                selectedCategory: category,
                categories: [category]
            )
            .environmentObject(SubscriptionManager.shared)
            .previewDisplayName("Add Mode")
            
            // Edit mode preview
            PromptSheet(
                viewContext: context,
                prompt: prompt,
                categories: [category]
            )
            .environmentObject(SubscriptionManager.shared)
            .previewDisplayName("Edit Mode")
        }
    }
}