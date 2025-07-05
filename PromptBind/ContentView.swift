//
//  ContentView.swift
//  PromptBind
//
//  Created by Sam Holstein on 5/28/25.
//

import SwiftUI
import CoreData

struct ContentView: View {
    // ViewModels for the lists
    @StateObject private var categoryListVM = CategoryListViewModel() // Uses default DataServiceImpl
    @StateObject private var promptListVM = PromptListViewModel()   // Uses default DataServiceImpl

    // State to hold the selected category
    @State private var selectedCategory: Category? = nil

    var body: some View {
        NavigationSplitView {
            // Sidebar: Category List
            CategoryListView(viewModel: categoryListVM, selectedCategory: $selectedCategory)
                .frame(minWidth: 200) // Give sidebar a min width
        } detail: {
            // Detail: Prompt List for the selected category
            PromptListView(viewModel: promptListVM)
                .onAppear {
                    // Ensure the promptListVM's selectedCategory is synced
                    // This might also be done with a .onChange on selectedCategory from ContentView
                    promptListVM.selectedCategory = selectedCategory
                }
                .onChange(of: selectedCategory) { oldCategory, newCategory in
                     promptListVM.selectedCategory = newCategory
                }
        }
        .environmentObject(categoryListVM)
        .onAppear {
            // Load initial categories and set a default selection if desired
            categoryListVM.loadCategories()
            if selectedCategory == nil, let firstCategory = categoryListVM.categories.first {
                selectedCategory = firstCategory
            }
            // Ensure promptListVM has the correct initial selected category
            promptListVM.selectedCategory = selectedCategory
        }
    }
}

#Preview {
    // Preview for ContentView needs to set up the environment and potentially mock data
    // This can get complex due to multiple ViewModels and Core Data.
    // For simplicity, we might skip a fully functional ContentView preview for now,
    // or build it out carefully if needed.
    
    // Example of a more robust preview setup:
    let persistenceController = PersistenceController.preview
    let dataService = DataServiceImpl(container: persistenceController.container)
    
    // Pre-populate with some data for preview
    let context = dataService.viewContext
    let cat1 = Category(context: context)
    cat1.name = "Preview General"
    cat1.order = 0
    
    let prompt1 = PromptItem(context: context)
    prompt1.id = UUID()
    prompt1.trigger = ";prev_trigger"
    prompt1.content = "This is a preview prompt."
    prompt1.category = cat1
    
    try? context.save()

    let categoryVM = CategoryListViewModel(dataService: dataService)
    let promptVM = PromptListViewModel(dataService: dataService)
    
    // To see something selected in preview:
    // categoryVM.loadCategories() // Load them
    // let firstCatInVM = categoryVM.categories.first
    // promptVM.selectedCategory = firstCatInVM
    // Note: Directly setting selectedCategory on promptVM in preview might not fully work without @State propagation.

    return ContentView()
        .environment(\.managedObjectContext, persistenceController.container.viewContext)
        // Provide VMs if they were not @StateObject but passed in,
        // but @StateObject handles its own initialization.
}
