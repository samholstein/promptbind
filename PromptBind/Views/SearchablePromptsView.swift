import SwiftUI
import CoreData

struct SearchablePromptsView: View {
    let viewContext: NSManagedObjectContext
    let categories: [NSManagedObject]
    
    @State private var searchText = ""
    @State private var editingPrompt: NSManagedObject?
    @State private var showingAddPrompt = false
    
    @FetchRequest private var allPrompts: FetchedResults<NSManagedObject>
    
    init(viewContext: NSManagedObjectContext, categories: [NSManagedObject]) {
        self.viewContext = viewContext
        self.categories = categories
        
        let request = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
        request.sortDescriptors = [NSSortDescriptor(key: "trigger", ascending: true)]
        _allPrompts = FetchRequest(fetchRequest: request)
    }
    
    var filteredPrompts: [NSManagedObject] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Array(allPrompts)
        } else {
            let searchTerm = searchText.lowercased()
            return allPrompts.filter { prompt in
                prompt.promptTrigger.lowercased().contains(searchTerm) ||
                prompt.promptExpansion.lowercased().contains(searchTerm) ||
                (prompt.promptCategory?.categoryName.lowercased().contains(searchTerm) ?? false)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search prompts...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                
                if !searchText.isEmpty {
                    Button("Clear") {
                        searchText = ""
                    }
                    .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            
            Divider()
            
            // Results
            if filteredPrompts.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: searchText.isEmpty ? "text.cursor" : "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text(searchText.isEmpty ? "No prompts yet" : "No results found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text(searchText.isEmpty ? "Create your first prompt to get started" : "Try a different search term")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if searchText.isEmpty {
                        Button("Add Prompt") {
                            showingAddPrompt = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.controlBackgroundColor).opacity(0.5))
            } else {
                List(filteredPrompts, id: \.objectID) { prompt in
                    VStack(alignment: .leading, spacing: 8) {
                        PromptRowView(prompt: prompt) {
                            editingPrompt = prompt
                        }
                        
                        // Show category and match info
                        HStack {
                            if let category = prompt.promptCategory {
                                Label(category.categoryName, systemImage: "folder")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if prompt.promptEnabled {
                                Label("Active", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Label("Disabled", systemImage: "slash.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Search Prompts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Prompt") {
                    showingAddPrompt = true
                }
            }
        }
        .sheet(isPresented: $showingAddPrompt) {
            AddPromptSheet(
                viewContext: viewContext,
                selectedCategory: nil,
                categories: categories
            )
        }
        .background(
            ManagedObjectSheetBinding(item: $editingPrompt) { prompt in
                EditPromptSheet(
                    viewContext: viewContext,
                    prompt: prompt,
                    categories: categories
                )
            }
        )
    }
}