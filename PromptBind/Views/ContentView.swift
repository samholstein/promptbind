import SwiftUI
import CoreData

// MARK: - Sidebar Selection Model
enum SidebarSelection: Hashable {
    case allPrompts
    case category(NSManagedObjectID)
    
    static func == (lhs: SidebarSelection, rhs: SidebarSelection) -> Bool {
        switch (lhs, rhs) {
        case (.allPrompts, .allPrompts):
            return true
        case (.category(let lhsID), .category(let rhsID)):
            return lhsID == rhsID
        default:
            return false
        }
    }
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case .allPrompts:
            hasher.combine("allPrompts")
        case .category(let id):
            hasher.combine("category")
            hasher.combine(id)
        }
    }
}

struct ContentView: View {
    let viewContext: NSManagedObjectContext
    @EnvironmentObject private var coreDataStack: CoreDataStack
    @EnvironmentObject private var cloudKitService: CloudKitService
    @EnvironmentObject private var windowManager: WindowManager
    var triggerMonitor: TriggerMonitorService?

    // Updated selection state
    @State private var selectedItem: SidebarSelection = .allPrompts
    @State private var showingAddPrompt = false
    
    // Fetch all categories, sorted by order then name
    @FetchRequest private var categories: FetchedResults<NSManagedObject>
    
    // Fetch all prompts for count display
    @FetchRequest private var allPrompts: FetchedResults<NSManagedObject>

    init(viewContext: NSManagedObjectContext, triggerMonitor: TriggerMonitorService?, cloudKitService: CloudKitService) {
        self.viewContext = viewContext
        self.triggerMonitor = triggerMonitor
        
        // Initialize FetchRequest for categories
        let categoryRequest = NSFetchRequest<NSManagedObject>(entityName: "Category")
        categoryRequest.sortDescriptors = [
            NSSortDescriptor(key: "order", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]
        _categories = FetchRequest(fetchRequest: categoryRequest)
        
        // Initialize FetchRequest for all prompts
        let promptRequest = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
        promptRequest.sortDescriptors = [NSSortDescriptor(key: "trigger", ascending: true)]
        _allPrompts = FetchRequest(fetchRequest: promptRequest)
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar: All Prompts + Categories
            VStack {
                // CloudKit status bar at top of sidebar
                cloudKitStatusBar
                
                // Sidebar content
                List(selection: $selectedItem) {
                    // All Prompts section
                    HStack {
                        Image(systemName: "text.cursor")
                            .foregroundColor(.blue)
                            .frame(width: 16)
                        Text("All Prompts")
                            .font(.body)
                        Spacer()
                        Text("\(allPrompts.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    .tag(SidebarSelection.allPrompts)
                    
                    // Categories section
                    if !categories.isEmpty {
                        Section("Categories") {
                            ForEach(categories, id: \.objectID) { category in
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.orange)
                                        .frame(width: 16)
                                    Text(category.categoryName)
                                        .font(.body)
                                    Spacer()
                                    Text("\(category.categoryPrompts.count)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                                .tag(SidebarSelection.category(category.objectID))
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle("PromptBind")
            }
        } detail: {
            // Detail: Show prompts based on selection
            detailView
        }
        .onAppear {
            print("ContentView: onAppear called")
            
            Task {
                await handleDefaultPrompts()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
            // Update trigger monitor when prompts change
            triggerMonitor?.loadAllPrompts()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: {
                    windowManager.openSettingsWindow()
                }) {
                    Label("Settings", systemImage: "gear")
                }
                .help("Settings")
                
                Button(action: {
                    showingAddPrompt = true
                }) {
                    Label("Add Prompt", systemImage: "plus")
                }
                .help("Add new prompt")
            }
        }
        .sheet(isPresented: $showingAddPrompt) {
            AddPromptSheet(
                viewContext: viewContext,
                selectedCategory: selectedCategory,
                categories: Array(categories)
            )
        }
    }
    
    // MARK: - Detail View
    @ViewBuilder
    private var detailView: some View {
        switch selectedItem {
        case .allPrompts:
            AllPromptsView(
                viewContext: viewContext,
                windowManager: windowManager,
                categories: Array(categories)
            )
        case .category(let categoryID):
            if let category = categories.first(where: { $0.objectID == categoryID }) {
                PromptsListView(
                    category: category,
                    viewContext: viewContext,
                    windowManager: windowManager,
                    categories: Array(categories)
                )
            } else {
                // Fallback if category not found
                AllPromptsView(
                    viewContext: viewContext,
                    windowManager: windowManager,
                    categories: Array(categories)
                )
            }
        }
    }
    
    // MARK: - Helper Properties
    private var selectedCategory: NSManagedObject? {
        switch selectedItem {
        case .allPrompts:
            return nil
        case .category(let categoryID):
            return categories.first(where: { $0.objectID == categoryID })
        }
    }
    
    private var cloudKitStatusBar: some View {
        Button(action: {
            windowManager.openSettingsWindow()
        }) {
            HStack {
                if coreDataStack.isCloudKitReady && coreDataStack.cloudKitError == nil {
                    Image(systemName: "icloud")
                        .foregroundColor(.blue)
                    Text("Synced")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Sync Issue")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(coreDataStack.isCloudKitReady ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(coreDataStack.cloudKitError ?? "Click to open Settings")
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private func handleDefaultPrompts() async {
        print("ContentView: handleDefaultPrompts started")
        
        let hasDefaultPrompts = await cloudKitService.hasAddedDefaultPrompts(context: viewContext)
        
        if !hasDefaultPrompts {
            print("ContentView: Adding default prompts...")
            await MainActor.run {
                addDefaultPrompts()
            }
        } else {
            print("ContentView: Default prompts already exist")
        }
    }
    
    private func addDefaultPrompts() {
        print("ContentView: Starting to add default prompts...")
        
        do {
            // Create default category using our extension
            let uncategorizedCategory = viewContext.createCategory(name: "Uncategorized", order: 0)
            
            print("ContentView: Created Uncategorized category")
            
            // Create test prompt using our extension
            let testPrompt = viewContext.createPrompt(
                trigger: "test",
                expansion: "This is a test prompt",
                enabled: true,
                category: uncategorizedCategory
            )
            
            print("ContentView: Created test prompt")
            
            // Save to Core Data (and CloudKit automatically)
            try viewContext.save()
            print("ContentView: Successfully saved default prompts to Core Data")
            
        } catch {
            print("ContentView: Error saving default prompts: \(error)")
            print("ContentView: Error details: \(error.localizedDescription)")
            if let coreDataError = error as NSError? {
                print("ContentView: Core Data error code: \(coreDataError.code)")
                print("ContentView: Core Data error domain: \(coreDataError.domain)")
                print("ContentView: Core Data error userInfo: \(coreDataError.userInfo)")
            }
        }
    }
}

/// List of prompts for a specific category
struct PromptsListView: View {
    let category: NSManagedObject
    let viewContext: NSManagedObjectContext
    let windowManager: WindowManager
    let categories: [NSManagedObject]
    
    @State private var showingAddPrompt = false
    @State private var editingPrompt: NSManagedObject?
    
    // Fetch prompts for this category
    @FetchRequest private var prompts: FetchedResults<NSManagedObject>
    
    init(category: NSManagedObject, viewContext: NSManagedObjectContext, windowManager: WindowManager, categories: [NSManagedObject]) {
        self.category = category
        self.viewContext = viewContext
        self.windowManager = windowManager
        self.categories = categories
        
        let request = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
        request.predicate = NSPredicate(format: "category == %@", category)
        request.sortDescriptors = [NSSortDescriptor(key: "trigger", ascending: true)]
        _prompts = FetchRequest(fetchRequest: request)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                    
                    Text(category.categoryName)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Button("Add Prompt") {
                        showingAddPrompt = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Text("\(prompts.count) prompt\(prompts.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            
            Divider()
            
            // Prompts list
            if prompts.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No prompts in this category")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Add your first prompt to get started")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button("Add Prompt") {
                        showingAddPrompt = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.controlBackgroundColor).opacity(0.5))
            } else {
                List(prompts, id: \.objectID) { prompt in
                    PromptRowView(prompt: prompt) {
                        editingPrompt = prompt
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            }
        }
        .sheet(isPresented: $showingAddPrompt) {
            AddPromptSheet(
                viewContext: viewContext,
                selectedCategory: category,
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

/// List showing all prompts regardless of category
struct AllPromptsView: View {
    let viewContext: NSManagedObjectContext
    let windowManager: WindowManager
    let categories: [NSManagedObject]
    
    @State private var showingAddPrompt = false
    @State private var editingPrompt: NSManagedObject?
    
    // Fetch all prompts
    @FetchRequest private var allPrompts: FetchedResults<NSManagedObject>
    
    init(viewContext: NSManagedObjectContext, windowManager: WindowManager, categories: [NSManagedObject]) {
        self.viewContext = viewContext
        self.windowManager = windowManager
        self.categories = categories
        
        let request = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
        request.sortDescriptors = [NSSortDescriptor(key: "trigger", ascending: true)]
        _allPrompts = FetchRequest(fetchRequest: request)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "text.cursor")
                        .foregroundColor(.blue)
                        .font(.title2)
                    
                    Text("All Prompts")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Button("Add Prompt") {
                        showingAddPrompt = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Text("\(allPrompts.count) prompt\(allPrompts.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            
            Divider()
            
            // All prompts list
            if allPrompts.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No prompts yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Create your first prompt to get started")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button("Add Prompt") {
                        showingAddPrompt = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.controlBackgroundColor).opacity(0.5))
            } else {
                List(allPrompts, id: \.objectID) { prompt in
                    VStack(alignment: .leading, spacing: 4) {
                        PromptRowView(prompt: prompt) {
                            editingPrompt = prompt
                        }
                        
                        // Show category name for context
                        if let category = prompt.promptCategory {
                            HStack {
                                Image(systemName: "folder")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(category.categoryName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.leading)
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
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

/// Individual prompt row component
struct PromptRowView: View {
    let prompt: NSManagedObject
    let onEdit: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Trigger text
                Text(prompt.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Enabled/disabled indicator
                if !prompt.promptEnabled {
                    Image(systemName: "slash.circle.fill")
                        .foregroundColor(.secondary)
                        .help("Disabled")
                }
                
                // Edit button
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Edit prompt")
            }
            
            // Expansion text
            Text(prompt.previewText)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separatorColor), lineWidth: 0.5)
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let coreDataStack = CoreDataStack.shared
        
        return ContentView(
            viewContext: coreDataStack.viewContext,
            triggerMonitor: nil,
            cloudKitService: CloudKitService()
        )
        .environmentObject(coreDataStack)
        .environmentObject(CloudKitService())
        .environmentObject(WindowManager.shared)
    }
}