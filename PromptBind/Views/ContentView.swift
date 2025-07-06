import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    
    @StateObject private var categoryListVM: CategoryListViewModel
    @StateObject private var promptListVM: PromptListViewModel
    @StateObject private var triggerMonitor: TriggerMonitorService
    
    @State private var selectedCategorySelection: CategorySelection? {
        didSet {
            promptListVM.selectedCategorySelection = selectedCategorySelection
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
            CategoryListView(viewModel: categoryListVM, selectedCategorySelection: $selectedCategorySelection, showingAddCategoryAlert: $showingAddCategoryAlert)
        } detail: {
            PromptListView(viewModel: promptListVM, promptToEdit: $promptToEdit)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            if promptListVM.selectedCategory != nil || selectedCategorySelection?.isAll == true || !categoryListVM.categories.isEmpty {
                                showingAddPromptSheet = true
                            } else {
                                print("No category selected and no categories exist to add prompt to.")
                            }
                        }) {
                            Label("Add Prompt", systemImage: "plus")
                        }
                        .disabled(selectedCategorySelection == nil && categoryListVM.categories.isEmpty)
                        .keyboardShortcut("n", modifiers: .command)
                    }
                }
        }
        .sheet(isPresented: $showingAddPromptSheet) {
            AddPromptView(viewModel: promptListVM, selectedCategorySelection: $selectedCategorySelection, categoryListVM: categoryListVM)
                .frame(minWidth: 500, idealWidth: 600, minHeight: 400) 
        }
        .sheet(item: $promptToEdit) { prompt in
            EditPromptView(viewModel: promptListVM, prompt: prompt, categoryListVM: categoryListVM)
                .frame(minWidth: 500, idealWidth: 600, minHeight: 450) 
        }
        .onAppear {
            triggerMonitor.startMonitoring()
            triggerMonitor.updatePrompts(promptListVM.prompts)
            if selectedCategorySelection == nil {
                selectedCategorySelection = .all
            }

            // Check if default prompts have been added before
            if !UserDefaults.standard.bool(forKey: "hasAddedDefaultPrompts") {
                // Add default prompts if none exist
                if promptListVM.prompts.isEmpty {
                    DefaultPromptsService.shared.addDefaultPromptsToContext(modelContext)
                    promptListVM.loadPrompts() // Reload prompts after adding defaults
                    // Set flag to true after adding defaults
                    UserDefaults.standard.set(true, forKey: "hasAddedDefaultPrompts")
                }
            }
        }
        .onDisappear {
            triggerMonitor.stopMonitoring()
        }
        .onChange(of: promptListVM.prompts) { _, newPrompts in
            triggerMonitor.updatePrompts(newPrompts)
        }
        .onChange(of: categoryListVM.categories) { _, newCategories in
            if let currentSelection = selectedCategorySelection {
                switch currentSelection {
                case .all:
                    break
                case .category(let category):
                    if !newCategories.contains(where: { $0.id == category.id }) {
                        selectedCategorySelection = .all
                    }
                }
            } else {
                selectedCategorySelection = .all
            }
        }
        .onChange(of: selectedCategorySelection) { _, newCategorySelection in
            promptListVM.selectedCategorySelection = newCategorySelection
        }
        .alert("New Category", isPresented: $showingAddCategoryAlert, actions: {
            TextField("Category Name", text: $newCategoryName)
            Button("Add", action: {
                categoryListVM.addCategory(name: newCategoryName)
                newCategoryName = ""
            })
            Button("Cancel", role: .cancel) { }
        }, message: {
            Text("Enter the name for the new category.")
        })
    }
}

// MARK: - AddPromptView
struct AddPromptView: View {
    @ObservedObject var viewModel: PromptListViewModel
    @Binding var selectedCategorySelection: CategorySelection?
    @ObservedObject var categoryListVM: CategoryListViewModel
    
    @State private var trigger: String = ""
    @State private var expansion: String = ""
    @State private var selectedCategoryForPrompt: Category?
    @Environment(\.dismiss) var dismiss
    
    @State private var showingValidationErrorAlert = false
    @State private var validationErrorMessage = ""

    var body: some View {
        NavigationView {
            Form {
                VStack(alignment: .leading, spacing: 15) {
                    Text("New Snippet").font(.title2)

                    LabeledContent {
                        TextField("e.g. ;hello", text: $trigger)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                    } label: {
                        Text("Trigger:")
                    }

                    LabeledContent {
                        TextEditor(text: $expansion)
                            .frame(minHeight: 150, maxHeight: .infinity)
                            .border(Color.gray.opacity(0.3), width: 1)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .frame(maxWidth: .infinity)
                    } label: {
                        Text("Expansion:")
                    }

                    LabeledContent {
                        Picker("Category", selection: $selectedCategoryForPrompt) {
                            ForEach(categoryListVM.categories) { category in
                                Text(category.name).tag(category as Category?)
                            }
                        }
                    } label: {
                        Text("Category:")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
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
                        viewModel.addPrompt(trigger: trigger, expansion: expansion, category: selectedCategoryForPrompt)
                        dismiss()
                    }
                    .disabled(trigger.isEmpty || expansion.isEmpty)
                }
            }
        }
        .onAppear {
            if let currentSelection = selectedCategorySelection {
                switch currentSelection {
                case .all:
                    selectedCategoryForPrompt = categoryListVM.categories.first
                case .category(let category):
                    selectedCategoryForPrompt = category
                }
            } else {
                selectedCategoryForPrompt = categoryListVM.categories.first
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
    @ObservedObject var categoryListVM: CategoryListViewModel

    @State private var trigger: String
    @State private var expansion: String
    @State private var selectedCategoryID: PersistentIdentifier?
    
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
                VStack(alignment: .leading, spacing: 15) {
                    Text("Edit Snippet").font(.title2)

                    LabeledContent {
                        TextField("Trigger", text: $trigger)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                    } label: {
                        Text("Trigger:")
                    }

                    LabeledContent {
                        TextEditor(text: $expansion)
                            .frame(minHeight: 150, maxHeight: .infinity)
                            .border(Color.gray.opacity(0.3), width: 1)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .frame(maxWidth: .infinity)
                    } label: {
                        Text("Expansion:")
                    }

                    LabeledContent {
                        Picker("Category", selection: $selectedCategoryID) {
                            Text("No Category").tag(nil as PersistentIdentifier?)
                            ForEach(categoryListVM.categories) { cat in
                                Text(cat.name).tag(cat.id as PersistentIdentifier?)
                            }
                        }
                    } label: {
                        Text("Category:")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
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
    @Binding var selectedCategorySelection: CategorySelection?
    @Binding var showingAddCategoryAlert: Bool

    @State private var showingRenameCategoryAlert = false
    @State private var categoryToRename: Category?
    @State private var renamedCategoryName: String = ""

    @State private var showingDeleteCategoryAlert = false
    @State private var categoryToDelete: Category?
    
    var body: some View {
        VStack(spacing: 0) { 
            List(selection: $selectedCategorySelection) {
                HStack {
                    Image(systemName: "list.bullet")
                        .foregroundColor(.accentColor)
                    Text("All")
                        .fontWeight(.medium)
                }
                .tag(CategorySelection.all)
                .onTapGesture {
                    selectedCategorySelection = .all
                }

                ForEach(viewModel.categories, id: \.id) { category in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundColor(.secondary)
                        Text(category.name)
                    }
                    .tag(CategorySelection.category(category))
                    .contextMenu {
                        Button("Rename") {
                            categoryToRename = category
                            renamedCategoryName = category.name
                            showingRenameCategoryAlert = true
                        }
                        Button("Delete", role: .destructive) {
                            if category.name == "Uncategorized" {
                                print("The 'Uncategorized' category cannot be deleted.")
                            } else {
                                categoryToDelete = category
                                showingDeleteCategoryAlert = true
                            }
                        }
                    }
                    .onTapGesture {
                        selectedCategorySelection = .category(category)
                    }
                }
                .onMove(perform: viewModel.reorderCategories)
                .onDelete { indexSet in
                    for index in indexSet {
                        let category = viewModel.categories[index]
                        if category.name == "Uncategorized" {
                            print("The 'Uncategorized' category cannot be deleted.")
                        } else {
                            categoryToDelete = category
                            showingDeleteCategoryAlert = true
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Categories")
            
            HStack(spacing: 8) {
                Button(action: {
                    showingAddCategoryAlert = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.borderless)
                .help("Add Category")
                
                Button(action: {
                    if let selectedCategorySelection = selectedCategorySelection,
                       case .category(let category) = selectedCategorySelection {
                        if category.name == "Uncategorized" {
                            print("The 'Uncategorized' category cannot be deleted via the toolbar button.")
                        } else {
                            categoryToDelete = category
                            showingDeleteCategoryAlert = true
                        }
                    }
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(canDeleteSelectedCategory ? .primary : .secondary)
                }
                .buttonStyle(.borderless)
                .disabled(!canDeleteSelectedCategory)
                .help("Delete Category")
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .border(Color(NSColor.separatorColor), width: 0.5)
        }
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
                if categoryToDel.name == "Uncategorized" {
                    print("The 'Uncategorized' category cannot be deleted.")
                    return
                }
                viewModel.deleteCategory(categoryToDel)
                if let currentSelection = selectedCategorySelection,
                   case .category(let selectedCategory) = currentSelection,
                   selectedCategory.id == categoryToDel.id {
                    selectedCategorySelection = .all
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: { categoryToDel in
            let promptCount = categoryToDel.prompts?.count ?? 0
            let promptText = promptCount == 1 ? "prompt" : "prompts"
            return Text("Are you sure you want to delete the category \"\(categoryToDel.name)\"? This will permanently delete all \(promptCount) \(promptText) in this category. This action cannot be undone.")
        }
    }
    
    private var canDeleteSelectedCategory: Bool {
        guard let selectedCategorySelection = selectedCategorySelection,
              case .category(let category) = selectedCategorySelection else {
            return false
        }
        return category.name != "Uncategorized"
    }
}

// MARK: - PromptListView
struct PromptListView: View {
    @ObservedObject var viewModel: PromptListViewModel
    @Binding var promptToEdit: Prompt? 
    
    @State private var showingDeleteAlert = false
    @State private var promptToDelete: Prompt?

    var body: some View {
        VStack {
            if let categorySelection = viewModel.selectedCategorySelection {
                Text(categorySelection.isAll ? "All Prompts" : "Prompts in \(categorySelection.displayName)")
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
                        .onTapGesture { 
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
            Text("Are you sure you want to delete the prompt with trigger \(promptToDel.trigger)? This action cannot be undone.")
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