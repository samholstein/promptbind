import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    
    @StateObject private var categoryListVM: CategoryListViewModel
    @StateObject private var promptListVM: PromptListViewModel
    @StateObject private var triggerMonitor: TriggerMonitorService
    
    @State private var selectedCategory: Category? {
        didSet {
            promptListVM.selectedCategory = selectedCategory
        }
    }
    
    @State private var showingAddPromptSheet = false
    @State private var showingAddCategoryAlert = false
    @State private var newCategoryName: String = ""

    // For editing prompts
    @State private var promptToEdit: Prompt?

    init(modelContext: ModelContext) {
        _categoryListVM = StateObject(wrappedValue: CategoryListViewModel(modelContext: modelContext))
        _promptListVM = StateObject(wrappedValue: PromptListViewModel(modelContext: modelContext))
        _triggerMonitor = StateObject(wrappedValue: TriggerMonitorService(modelContext: modelContext))
    }
    
    var body: some View {
        NavigationSplitView {
            CategoryListView(viewModel: categoryListVM, selectedCategory: $selectedCategory)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            newCategoryName = ""
                            showingAddCategoryAlert = true
                        }) {
                            Label("Add Category", systemImage: "plus.circle.fill")
                        }
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                    }
                }
                .alert("New Category", isPresented: $showingAddCategoryAlert, actions: {
                    TextField("Category Name", text: $newCategoryName)
                    Button("Add", action: {
                        categoryListVM.addCategory(name: newCategoryName)
                    })
                    Button("Cancel", role: .cancel) { }
                }, message: {
                    Text("Enter the name for the new category.")
                })
        } detail: {
            PromptListView(viewModel: promptListVM, promptToEdit: $promptToEdit)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            if promptListVM.selectedCategory != nil || !categoryListVM.categories.isEmpty {
                                showingAddPromptSheet = true
                            } else {
                                print("No category selected and no categories exist to add prompt to.")
                            }
                        }) {
                            Label("Add Prompt", systemImage: "plus")
                        }
                        .disabled(promptListVM.selectedCategory == nil && categoryListVM.categories.isEmpty)
                        .keyboardShortcut("n", modifiers: .command)
                    }
                }
        }
        .sheet(isPresented: $showingAddPromptSheet) {
            AddPromptView(viewModel: promptListVM, selectedCategory: $selectedCategory)
        }
        .sheet(item: $promptToEdit) { prompt in
            EditPromptView(viewModel: promptListVM, prompt: prompt, categoryListVM: categoryListVM)
        }
        .onAppear {
            triggerMonitor.startMonitoring()
            triggerMonitor.updatePrompts(promptListVM.prompts)
            // Ensure a category is selected on launch if categories exist
            if selectedCategory == nil && !categoryListVM.categories.isEmpty {
                selectedCategory = categoryListVM.categories.first
            }
        }
        .onDisappear {
            triggerMonitor.stopMonitoring()
        }
        .onChange(of: promptListVM.prompts) { _, newPrompts in
            triggerMonitor.updatePrompts(newPrompts)
        }
        .onChange(of: categoryListVM.categories) { _, newCategories in
            if selectedCategory == nil || !newCategories.contains(where: { $0.id == selectedCategory?.id }) {
                selectedCategory = newCategories.first
            }
        }
    }
}

// MARK: - AddPromptView
struct AddPromptView: View {
    @ObservedObject var viewModel: PromptListViewModel
    @Binding var selectedCategory: Category?
    
    @State private var trigger: String = ""
    @State private var expansion: String = ""
    @Environment(\.dismiss) var dismiss
    
    @State private var showingValidationErrorAlert = false
    @State private var validationErrorMessage = ""

    var body: some View {
        NavigationView {
            Form {
                TextField("Trigger (e.g. ;hello)", text: $trigger)
                TextEditor(text: $expansion)
                    .frame(minHeight: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }
            .navigationTitle("Add Snippet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            validationErrorMessage = "Trigger cannot be empty."
                            showingValidationErrorAlert = true
                            return
                        }
                        if expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            validationErrorMessage = "Expansion cannot be empty."
                            showingValidationErrorAlert = true
                            return
                        }
                        viewModel.addPrompt(trigger: trigger, expansion: expansion, category: selectedCategory)
                        dismiss()
                    }
                    .disabled(trigger.isEmpty || expansion.isEmpty)
                }
            }
        }
        .alert("Validation Error", isPresented: $showingValidationErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationErrorMessage)
        }
    }
}

// MARK: - EditPromptView
struct EditPromptView: View {
    @ObservedObject var viewModel: PromptListViewModel
    let prompt: Prompt
    @ObservedObject var categoryListVM: CategoryListViewModel // To get all categories

    @State private var trigger: String
    @State private var expansion: String
    @State private var selectedCategoryID: PersistentIdentifier? // Use PersistentIdentifier for category selection
    
    @Environment(\.dismiss) var dismiss
    
    @State private var showingValidationErrorAlert = false
    @State private var validationErrorMessage = ""

    init(viewModel: PromptListViewModel, prompt: Prompt, categoryListVM: CategoryListViewModel) {
        self.viewModel = viewModel
        self.prompt = prompt
        self.categoryListVM = categoryListVM
        _trigger = State(initialValue: prompt.trigger)
        _expansion = State(initialValue: prompt.expansion)
        _selectedCategoryID = State(initialValue: prompt.category?.id)
    }

    var body: some View {
        NavigationView {
            Form {
                TextField("Trigger", text: $trigger)
                TextEditor(text: $expansion)
                    .frame(minHeight: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                Picker("Category", selection: $selectedCategoryID) {
                    Text("No Category").tag(nil as PersistentIdentifier?)
                    ForEach(categoryListVM.categories) { cat in
                        Text(cat.name).tag(cat.id as PersistentIdentifier?)
                    }
                }
            }
            .navigationTitle("Edit Snippet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Changes") {
                        if trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            validationErrorMessage = "Trigger cannot be empty."
                            showingValidationErrorAlert = true
                            return
                        }
                        if expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            validationErrorMessage = "Expansion cannot be empty."
                            showingValidationErrorAlert = true
                            return
                        }
                        let newCategory = categoryListVM.categories.first(where: { $0.id == selectedCategoryID })
                        viewModel.updatePrompt(prompt, newTrigger: trigger, newExpansion: expansion, newCategory: newCategory)
                        dismiss()
                    }
                    .disabled(trigger.isEmpty || expansion.isEmpty)
                }
            }
        }
        .alert("Validation Error", isPresented: $showingValidationErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationErrorMessage)
        }
    }
}


// MARK: - CategoryListView
struct CategoryListView: View {
    @ObservedObject var viewModel: CategoryListViewModel
    @Binding var selectedCategory: Category?

    @State private var showingRenameCategoryAlert = false
    @State private var categoryToRename: Category?
    @State private var renamedCategoryName: String = ""

    @State private var showingDeleteCategoryAlert = false
    @State private var categoryToDelete: Category?
    
    var body: some View {
        List(selection: $selectedCategory) {
            ForEach(viewModel.categories) { category in
                Text(category.name)
                    .tag(category as Category?)
                    .contextMenu {
                        Button("Rename") {
                            categoryToRename = category
                            renamedCategoryName = category.name
                            showingRenameCategoryAlert = true
                        }
                        Button("Delete", role: .destructive) {
                            categoryToDelete = category
                            showingDeleteCategoryAlert = true
                        }
                    }
            }
            .onMove(perform: viewModel.reorderCategories)
        }
        .listStyle(.sidebar)
        .navigationTitle("Categories")
        .alert("Rename Category", isPresented: $showingRenameCategoryAlert, presenting: categoryToRename) { categoryToEdit in
            TextField("New Name", text: $renamedCategoryName)
            Button("Rename") {
                viewModel.renameCategory(categoryToEdit, newName: renamedCategoryName)
            }
            Button("Cancel", role: .cancel) { }
        } message: { categoryToEdit in
            Text("Enter the new name for \"\(categoryToEdit.name)\".")
        }
        .alert("Delete Category", isPresented: $showingDeleteCategoryAlert, presenting: categoryToDelete) { categoryToDel in
            Button("Delete", role: .destructive) {
                viewModel.deleteCategory(categoryToDel)
                // If the selected category is deleted, nil it out or re-select first available
                if selectedCategory?.id == categoryToDel.id {
                    selectedCategory = viewModel.categories.first
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: { categoryToDel in
            Text("Are you sure you want to delete the category \"\(categoryToDel.name)\"? All prompts within this category will be moved to 'Uncategorized'. This action cannot be undone.")
        }
    }
}

// MARK: - PromptListView
struct PromptListView: View {
    @ObservedObject var viewModel: PromptListViewModel
    @Binding var promptToEdit: Prompt? // Bind to the state in ContentView
    
    @State private var showingDeleteAlert = false
    @State private var promptToDelete: Prompt?

    var body: some View {
        VStack {
            if let category = viewModel.selectedCategory {
                Text("Prompts in \(category.name)")
                    .font(.headline)
                    .padding(.top)
                
                List {
                    ForEach(viewModel.prompts) { prompt in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(prompt.trigger)
                                    .font(.title3)
                                Text(prompt.expansion)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { prompt.enabled },
                                set: { newValue in
                                    prompt.enabled = newValue
                                    // No need to update trigger monitor here, onChange in ContentView handles it
                                }
                            ))
                        }
                        .contextMenu {
                            Button {
                                promptToEdit = prompt
                            } label: {
                                Label("Edit Prompt", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                promptToDelete = prompt
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete Prompt", systemImage: "trash")
                            }
                        }
                        .onTapGesture { // Allow tapping row for editing
                            promptToEdit = prompt
                        }
                    }
                    .onDelete(perform: deletePrompts)
                }
            } else {
                Text("Select a category to see its prompts, or add a new category and prompts.")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Prompts")
        .alert("Delete Prompt", isPresented: $showingDeleteAlert, presenting: promptToDelete) { promptToDel in
            Button("Delete", role: .destructive) {
                viewModel.deletePrompt(promptToDel)
            }
            Button("Cancel", role: .cancel) {}
        } message: { promptToDel in
            Text("Are you sure you want to delete the prompt with trigger \"\(promptToDel.trigger)\"? This action cannot be undone.")
        }
    }
    
    private func deletePrompts(offsets: IndexSet) {
        for index in offsets {
            viewModel.deletePrompt(viewModel.prompts[index])
        }
    }
}

#Preview {
    ContentView(modelContext: try! ModelContainer(for: Prompt.self, Category.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)).mainContext)
        .modelContainer(for: [Prompt.self, Category.self], inMemory: true)
}