import SwiftUI
import CoreData // For NSManagedObjectID

struct PromptListView: View {
    @StateObject var viewModel: PromptListViewModel
    @State private var showingAddPromptSheet = false
    
    @State private var showingEditPromptSheet = false
    @State private var promptToEdit: PromptItem?

    @State private var showingDeleteAlert = false
    @State private var promptToDelete: PromptItem?

    var body: some View {
        VStack {
            if let category = viewModel.selectedCategory {
                Text("Prompts in \(category.name ?? "Selected Category")")
                    .font(.headline)
                    .padding(.top)
                
                List {
                    ForEach(viewModel.prompts) { prompt in
                        HStack { 
                            VStack(alignment: .leading) {
                                Text(prompt.trigger ?? "No Trigger").font(.title3)
                                Text(prompt.content ?? "No Content")
                                    .font(.caption)
                                    .lineLimit(2)
                                    .foregroundColor(.gray)
                            }
                            Spacer() 
                        }
                        .contextMenu {
                            Button {
                                promptToEdit = prompt
                                showingEditPromptSheet = true
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
                            showingEditPromptSheet = true
                        }
                    }
                }
            } else {
                Text("Select a category to see its prompts.")
                    .foregroundColor(.secondary)
            }
        }
        .toolbar {
            ToolbarItem {
                Button(action: {
                    if viewModel.selectedCategory != nil {
                        showingAddPromptSheet = true
                    } else {
                        print("No category selected to add prompt to.")
                    }
                }) {
                    Label("Add Prompt", systemImage: "plus")
                }
                .disabled(viewModel.selectedCategory == nil)
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $showingAddPromptSheet) {
            if let selectedCat = viewModel.selectedCategory {
                 AddPromptView(viewModel: viewModel, category: selectedCat)
            }
        }
        .sheet(item: $promptToEdit) { prompt in 
            EditPromptView(viewModel: viewModel, prompt: prompt)
        }
        .alert("Delete Prompt", isPresented: $showingDeleteAlert, presenting: promptToDelete) { promptToDel in
            Button("Delete", role: .destructive) {
                viewModel.deletePrompt(promptToDel)
            }
            Button("Cancel", role: .cancel) {}
        } message: { promptToDel in
            Text("Are you sure you want to delete the prompt with trigger \"\(promptToDel.trigger ?? "")\"? This action cannot be undone.")
        }
    }
}

struct AddPromptView: View {
    @ObservedObject var viewModel: PromptListViewModel
    var category: Category
    
    @State private var trigger: String = ""
    @State private var content: String = ""
    @Environment(\.dismiss) var dismiss
    
    @State private var showingValidationErrorAlert = false
    @State private var validationErrorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("New Prompt in \(category.name ?? "Category")")
                .font(.title2)
                .padding(.bottom)
            
            LabeledContent { 
                TextField("e.g., ;eml", text: $trigger)
                    .textFieldStyle(.roundedBorder)
            } label: {
                Text("Trigger:")
            }

            LabeledContent { 
                TextEditor(text: $content)
                    .frame(height: 150) 
                    .border(Color.gray.opacity(0.3), width: 1)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } label: {
                Text("Content:")
            }
            
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save") {
                    if trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        validationErrorMessage = "Trigger cannot be empty."
                        showingValidationErrorAlert = true
                        return
                    }
                    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        validationErrorMessage = "Content cannot be empty."
                        showingValidationErrorAlert = true
                        return
                    }
                    viewModel.addPrompt(trigger: trigger, content: content, category: category)
                    dismiss()
                }
                .disabled(trigger.isEmpty || content.isEmpty) 
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 450, height: 380) 
        .alert("Validation Error", isPresented: $showingValidationErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationErrorMessage)
        }
    }
}

struct EditPromptView: View {
    @ObservedObject var viewModel: PromptListViewModel
    let prompt: PromptItem 
    
    @State private var trigger: String
    @State private var content: String
    @State private var selectedCategoryID: NSManagedObjectID? 
    
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var categoryListVM: CategoryListViewModel 

    @State private var showingValidationErrorAlert = false
    @State private var validationErrorMessage = ""

    init(viewModel: PromptListViewModel, prompt: PromptItem) {
        self.viewModel = viewModel
        self.prompt = prompt
        _trigger = State(initialValue: prompt.trigger ?? "")
        _content = State(initialValue: prompt.content ?? "")
        _selectedCategoryID = State(initialValue: prompt.category?.objectID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Edit Prompt").font(.title2).padding(.bottom)
            
            LabeledContent {
                TextField("Trigger", text: $trigger)
                    .textFieldStyle(.roundedBorder)
            } label: {
                Text("Trigger:")
            }

            LabeledContent {
                 TextEditor(text: $content)
                    .frame(height: 150)
                    .border(Color.gray.opacity(0.3), width: 1)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } label: {
                Text("Content:")
            }
            
            LabeledContent {
                Picker("Category", selection: $selectedCategoryID) {
                    Text("No Category").tag(nil as NSManagedObjectID?) 
                    ForEach(categoryListVM.categories) { cat in
                        Text(cat.name ?? "Untitled").tag(cat.objectID as NSManagedObjectID?)
                    }
                }
            } label: {
                 Text("Category:")
            }
            
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save Changes") {
                    if trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        validationErrorMessage = "Trigger cannot be empty."
                        showingValidationErrorAlert = true
                        return
                    }
                    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        validationErrorMessage = "Content cannot be empty."
                        showingValidationErrorAlert = true
                        return
                    }

                    let newCategory = categoryListVM.categories.first(where: { $0.objectID == selectedCategoryID })
                    viewModel.updatePrompt(prompt, newTrigger: trigger, newContent: content, newCategory: newCategory)
                    dismiss()
                }
                 .disabled(trigger.isEmpty || content.isEmpty)
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 450, height: 420) 
        .alert("Validation Error", isPresented: $showingValidationErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationErrorMessage)
        }
        .onAppear {
            if categoryListVM.categories.isEmpty {
                 categoryListVM.loadCategories()
            }
        }
    }
}