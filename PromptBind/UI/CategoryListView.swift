import SwiftUI

struct CategoryListView: View {
    @StateObject var viewModel: CategoryListViewModel
    @Binding var selectedCategory: Category?

    @State private var showingAddCategoryAlert = false
    @State private var newCategoryName: String = ""

    @State private var showingRenameCategoryAlert = false
    @State private var categoryToRename: Category?
    @State private var renamedCategoryName: String = ""

    @State private var showingDeleteCategoryAlert = false
    @State private var categoryToDelete: Category?
    
    var body: some View {
        VStack {
            List(selection: $selectedCategory) {
                ForEach(viewModel.categories) { category in
                    Text(category.name ?? "Untitled Category")
                        .tag(category as Category?)
                        .contextMenu {
                            Button("Rename") {
                                categoryToRename = category
                                renamedCategoryName = category.name ?? ""
                                showingRenameCategoryAlert = true
                            }
                            Button("Delete", role: .destructive) {
                                categoryToDelete = category
                                showingDeleteCategoryAlert = true
                            }
                        }
                }
                .onMove(perform: moveCategories)
            }
            .listStyle(.sidebar)
            .navigationTitle("Categories") 
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        newCategoryName = ""
                        showingAddCategoryAlert = true
                    }) {
                        Label("Add Category", systemImage: "plus.circle.fill")
                    }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                }
            }
        }
        .alert("New Category", isPresented: $showingAddCategoryAlert, actions: {
            TextField("Category Name", text: $newCategoryName)
            Button("Add", action: {
                viewModel.addCategory(name: newCategoryName)
            })
            Button("Cancel", role: .cancel) { }
        }, message: {
            Text("Enter the name for the new category.")
        })
        .alert("Rename Category", isPresented: $showingRenameCategoryAlert, presenting: categoryToRename) { categoryToEdit in
            TextField("New Name", text: $renamedCategoryName)
            Button("Rename") {
                viewModel.renameCategory(categoryToEdit, newName: renamedCategoryName)
            }
            Button("Cancel", role: .cancel) { }
        } message: { categoryToEdit in
            Text("Enter the new name for \"\(categoryToEdit.name ?? "")\".")
        }
        .alert("Delete Category", isPresented: $showingDeleteCategoryAlert, presenting: categoryToDelete) { categoryToDel in
            Button("Delete", role: .destructive) {
                viewModel.deleteCategory(categoryToDel)
            }
            Button("Cancel", role: .cancel) { }
        } message: { categoryToDel in
            Text("Are you sure you want to delete the category \"\(categoryToDel.name ?? "")\"? All prompts within this category will also be deleted. This action cannot be undone.")
        }
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first else { return }
        viewModel.reorderCategories(from: sourceIndex, to: destination)
    }
}