import SwiftUI
import CoreData

// MARK: - Focus Management
struct SelectedSidebarItemKey: FocusedValueKey {
    typealias Value = Binding<SidebarSelection>
}

extension FocusedValues {
    var selectedSidebarItem: Binding<SidebarSelection>? {
        get { self[SelectedSidebarItemKey.self] }
        set { self[SelectedSidebarItemKey.self] = newValue }
    }
}

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
    
    // MARK: - Accessibility Support
    var accessibilityLabel: String {
        switch self {
        case .allPrompts:
            return "All Prompts"
        case .category:
            return "Category"
        }
    }
    
    var accessibilityHint: String {
        switch self {
        case .allPrompts:
            return "View all prompts across all categories"
        case .category:
            return "View prompts in this category"
        }
    }
}

struct ContentView: View {
    let viewContext: NSManagedObjectContext
    @EnvironmentObject private var coreDataStack: CoreDataStack
    @EnvironmentObject private var cloudKitService: CloudKitService
    @EnvironmentObject private var windowManager: WindowManager
    var triggerMonitor: TriggerMonitorService?

    // Updated selection state with persistence
    @State private var selectedItem: SidebarSelection = .allPrompts
    @State private var showingAddPrompt = false
    
    // Performance optimization: Limit fetch results
    @FetchRequest private var categories: FetchedResults<NSManagedObject>
    @FetchRequest private var allPrompts: FetchedResults<NSManagedObject>
    
    // MARK: - Selection Persistence
    private let selectedItemKey = "PromptBind.SelectedSidebarItem"
    
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
        
        // Load selected item from UserDefaults
        if let savedItem = UserDefaults.standard.object(forKey: selectedItemKey) as? String {
            switch savedItem {
            case "allPrompts":
                selectedItem = .allPrompts
            case "category":
                if let categoryID = UserDefaults.standard.object(forKey: "PromptBind.SelectedCategoryID") as? NSManagedObjectID {
                    selectedItem = .category(categoryID)
                }
            default:
                break
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar: All Prompts + Categories
            VStack(spacing: 0) {
                // CloudKit status bar at top of sidebar
                cloudKitStatusBar
                
                // Sidebar content
                List(selection: $selectedItem) {
                    // All Prompts section
                    SidebarRowView(
                        icon: "text.cursor",
                        iconColor: .blue,
                        title: "All Prompts",
                        count: allPrompts.count,
                        isSelected: selectedItem == .allPrompts
                    )
                    .tag(SidebarSelection.allPrompts)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .listRowSeparator(.hidden)
                    
                    // Categories section
                    if !categories.isEmpty {
                        Section {
                            ForEach(categories, id: \.objectID) { category in
                                SidebarRowView(
                                    icon: "folder.fill",
                                    iconColor: .orange,
                                    title: category.categoryName,
                                    count: category.categoryPrompts.count,
                                    isSelected: selectedItem == .category(category.objectID)
                                )
                                .tag(SidebarSelection.category(category.objectID))
                                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                                .listRowSeparator(.hidden)
                            }
                        } header: {
                            HStack {
                                Text("Categories")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                        }
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle("PromptBind")
                .scrollContentBackground(.hidden)
                .focusedSceneValue(\.selectedSidebarItem, $selectedItem)
                .onKeyPress(.upArrow) {
                    navigateUp()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    navigateDown()
                    return .handled
                }
            }
        } detail: {
            // Detail: Show prompts based on selection
            detailView
        }
        .onAppear {
            print("ContentView: onAppear called")
            
            // Restore selection state
            restoreSelectedItem()
            
            Task {
                await handleDefaultPrompts()
            }
        }
        .onChange(of: selectedItem) { oldValue, newValue in
            // Persist selection changes
            saveSelectedItem(newValue)
            
            // Log for debugging
            print("ContentView: Selection changed from \(oldValue) to \(newValue)")
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
            // Update trigger monitor when prompts change
            triggerMonitor?.loadAllPrompts()
            
            // Validate current selection is still valid
            validateCurrentSelection()
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
                categories: Array(categories),
                isLoading: categories.isEmpty && allPrompts.isEmpty
            )
        case .category(let categoryID):
            if let category = categories.first(where: { $0.objectID == categoryID }) {
                PromptsListView(
                    category: category,
                    viewContext: viewContext,
                    windowManager: windowManager,
                    categories: Array(categories),
                    isLoading: false
                )
            } else {
                // Fallback if category not found - show loading or error state
                CategoryNotFoundView(
                    categoryID: categoryID,
                    onSelectAllPrompts: {
                        selectedItem = .allPrompts
                    }
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
            HStack(spacing: 8) {
                if coreDataStack.isCloudKitReady && coreDataStack.cloudKitError == nil {
                    Image(systemName: "icloud.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 12, weight: .medium))
                    Text("Synced")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 12, weight: .medium))
                    Text("Sync Issue")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                }
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(coreDataStack.isCloudKitReady ? Color.blue.opacity(0.08) : Color.orange.opacity(0.08))
                    .stroke(coreDataStack.isCloudKitReady ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(coreDataStack.cloudKitError ?? "Click to open Settings")
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
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
    
    // MARK: - Selection Persistence & Validation
    
    private func saveSelectedItem(_ item: SidebarSelection) {
        switch item {
        case .allPrompts:
            UserDefaults.standard.set("allPrompts", forKey: selectedItemKey)
        case .category(let objectID):
            UserDefaults.standard.set("category:\(objectID.uriRepresentation().absoluteString)", forKey: selectedItemKey)
        }
    }
    
    private func restoreSelectedItem() {
        guard let savedString = UserDefaults.standard.string(forKey: selectedItemKey) else {
            selectedItem = .allPrompts
            return
        }
        
        if savedString == "allPrompts" {
            selectedItem = .allPrompts
        } else if savedString.hasPrefix("category:") {
            let urlString = String(savedString.dropFirst("category:".count))
            if let url = URL(string: urlString),
               let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url) {
                
                // Validate that the category still exists
                if categories.contains(where: { $0.objectID == objectID }) {
                    selectedItem = .category(objectID)
                } else {
                    // Category no longer exists, default to all prompts
                    selectedItem = .allPrompts
                    UserDefaults.standard.removeObject(forKey: selectedItemKey)
                }
            } else {
                // Invalid URL, default to all prompts
                selectedItem = .allPrompts
                UserDefaults.standard.removeObject(forKey: selectedItemKey)
            }
        } else {
            // Invalid saved value, default to all prompts
            selectedItem = .allPrompts
            UserDefaults.standard.removeObject(forKey: selectedItemKey)
        }
    }
    
    private func validateCurrentSelection() {
        switch selectedItem {
        case .allPrompts:
            // Always valid
            break
        case .category(let objectID):
            // Check if category still exists
            if !categories.contains(where: { $0.objectID == objectID }) {
                print("ContentView: Selected category no longer exists, switching to All Prompts")
                selectedItem = .allPrompts
            }
        }
    }
    
    // MARK: - Performance Optimization
    
    private func optimizedCategoryFetch() -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Category")
        request.sortDescriptors = [
            NSSortDescriptor(key: "order", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]
        request.fetchBatchSize = 20 // Optimize for typical usage
        request.relationshipKeyPathsForPrefetching = ["prompts"] // Prefetch relationships
        return request
    }
    
    private func optimizedPromptFetch() -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
        request.sortDescriptors = [NSSortDescriptor(key: "trigger", ascending: true)]
        request.fetchBatchSize = 50 // Optimize for larger prompt lists
        request.relationshipKeyPathsForPrefetching = ["category"] // Prefetch category relationships
        return request
    }
    
    // MARK: - Keyboard Navigation
    
    private func navigateUp() {
        switch selectedItem {
        case .allPrompts:
            // Already at top, do nothing
            break
        case .category(let objectID):
            if let currentIndex = categories.firstIndex(where: { $0.objectID == objectID }) {
                if currentIndex > 0 {
                    // Move to previous category
                    let previousCategory = categories[currentIndex - 1]
                    selectedItem = .category(previousCategory.objectID)
                } else {
                    // Move to "All Prompts"
                    selectedItem = .allPrompts
                }
            }
        }
    }
    
    private func navigateDown() {
        switch selectedItem {
        case .allPrompts:
            // Move to first category if available
            if let firstCategory = categories.first {
                selectedItem = .category(firstCategory.objectID)
            }
        case .category(let objectID):
            if let currentIndex = categories.firstIndex(where: { $0.objectID == objectID }),
               currentIndex < categories.count - 1 {
                // Move to next category
                let nextCategory = categories[currentIndex + 1]
                selectedItem = .category(nextCategory.objectID)
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
    let isLoading: Bool
    
    @State private var showingAddPrompt = false
    @State private var editingPrompt: NSManagedObject?
    
    // Fetch prompts for this category
    @FetchRequest private var prompts: FetchedResults<NSManagedObject>
    
    init(category: NSManagedObject, viewContext: NSManagedObjectContext, windowManager: WindowManager, categories: [NSManagedObject], isLoading: Bool = false) {
        self.category = category
        self.viewContext = viewContext
        self.windowManager = windowManager
        self.categories = categories
        self.isLoading = isLoading
        
        let request = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
        request.predicate = NSPredicate(format: "category == %@", category)
        request.sortDescriptors = [NSSortDescriptor(key: "trigger", ascending: true)]
        _prompts = FetchRequest(fetchRequest: request)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            CategoryHeaderView(
                icon: "folder.fill",
                iconColor: .orange,
                title: category.categoryName,
                count: prompts.count,
                onAddPrompt: {
                    showingAddPrompt = true
                }
            )
            
            Divider()
            
            // Content
            if isLoading {
                LoadingStateView(message: "Loading prompts...")
            } else if prompts.isEmpty {
                EmptyStateView(
                    icon: "text.cursor",
                    title: "No prompts in this category",
                    subtitle: "Add your first prompt to get started",
                    buttonTitle: "Add Prompt",
                    onButtonTap: {
                        showingAddPrompt = true
                    }
                )
            } else {
                PromptsListContentView(prompts: Array(prompts)) { prompt in
                    editingPrompt = prompt
                }
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
    let isLoading: Bool
    
    @State private var showingAddPrompt = false
    @State private var editingPrompt: NSManagedObject?
    
    // Fetch all prompts
    @FetchRequest private var allPrompts: FetchedResults<NSManagedObject>
    
    init(viewContext: NSManagedObjectContext, windowManager: WindowManager, categories: [NSManagedObject], isLoading: Bool = false) {
        self.viewContext = viewContext
        self.windowManager = windowManager
        self.categories = categories
        self.isLoading = isLoading
        
        let request = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
        request.sortDescriptors = [NSSortDescriptor(key: "trigger", ascending: true)]
        _allPrompts = FetchRequest(fetchRequest: request)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            CategoryHeaderView(
                icon: "text.cursor",
                iconColor: .blue,
                title: "All Prompts",
                count: allPrompts.count,
                onAddPrompt: {
                    showingAddPrompt = true
                }
            )
            
            Divider()
            
            // Content
            if isLoading {
                LoadingStateView(message: "Loading prompts...")
            } else if allPrompts.isEmpty {
                EmptyStateView(
                    icon: "text.cursor",
                    title: "No prompts yet",
                    subtitle: "Create your first prompt to get started",
                    buttonTitle: "Add Prompt",
                    onButtonTap: {
                        showingAddPrompt = true
                    }
                )
            } else {
                AllPromptsListContentView(prompts: Array(allPrompts)) { prompt in
                    editingPrompt = prompt
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

/// Individual prompt row component - completely redesigned
struct PromptRowView: View {
    let prompt: NSManagedObject
    let onEdit: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left side: Bind and preview
            VStack(alignment: .leading, spacing: 3) {
                // Bind text (trigger)
                Text(prompt.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                
                // Prompt preview - actual expansion text
                Text(prompt.promptExpansion.isEmpty ? "No content" : prompt.promptExpansion)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            Spacer()
            
            // Right side: Status and actions
            HStack(spacing: 8) {
                // Enabled/disabled indicator
                if !prompt.promptEnabled {
                    Image(systemName: "pause.circle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))
                        .help("Disabled")
                }
                
                // Edit button
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundColor(.blue)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Edit prompt")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
    }
}

/// Enhanced sidebar row component with better styling
struct SidebarRowView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let count: Int
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 18, height: 18)
                .font(.system(size: 14, weight: .medium))
                .accessibilityHidden(true) // Icon is decorative
            
            // Title
            Text(title)
                .font(.body)
                .fontWeight(isSelected ? .medium : .regular)
                .foregroundColor(isSelected ? .primary : .primary)
            
            Spacer()
            
            // Count badge
            Text("\(count)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                )
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count) prompt\(count == 1 ? "" : "s")")
        .accessibilityHint(isSelected ? "Currently selected" : "Tap to view prompts")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Error state when selected category is not found
struct CategoryNotFoundView: View {
    let categoryID: NSManagedObjectID
    let onSelectAllPrompts: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            VStack(spacing: 8) {
                Text("Category Not Found")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("The selected category might have been deleted or is no longer available.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("View All Prompts") {
                onSelectAllPrompts()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }
}

/// Loading state component
struct LoadingStateView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.2)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }
}

/// Reusable header component for detail views
struct CategoryHeaderView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let count: Int
    let onAddPrompt: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.title2)
                
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Add Prompt") {
                    onAddPrompt()
                }
                .buttonStyle(.borderedProminent)
            }
            
            Text("\(count) prompt\(count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
    }
}

/// Reusable empty state component
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    let buttonTitle: String
    let onButtonTap: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(buttonTitle) {
                onButtonTap()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }
}

/// Content view for prompts list (category-specific) - simplified
struct PromptsListContentView: View {
    let prompts: [NSManagedObject]
    let onEdit: (NSManagedObject) -> Void
    
    var body: some View {
        List(prompts, id: \.objectID) { prompt in
            PromptRowView(prompt: prompt) {
                onEdit(prompt)
            }
            .listRowSeparator(.visible)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
        .listStyle(.plain)
        .background(Color(.controlBackgroundColor))
    }
}

/// Content view for all prompts list (with category context) - simplified
struct AllPromptsListContentView: View {
    let prompts: [NSManagedObject]
    let onEdit: (NSManagedObject) -> Void
    
    var body: some View {
        List(prompts, id: \.objectID) { prompt in
            VStack(alignment: .leading, spacing: 0) {
                PromptRowView(prompt: prompt) {
                    onEdit(prompt)
                }
                
                // Show category name for context
                if let category = prompt.promptCategory {
                    HStack {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(category.categoryName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .listRowSeparator(.visible)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
        .listStyle(.plain)
        .background(Color(.controlBackgroundColor))
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