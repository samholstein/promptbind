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
    
    // NOTE: Explicit Equatable conformance is needed for some older compiler versions.
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
            hasher.combine(id)
        }
    }
}

struct ContentView: View {
    let viewContext: NSManagedObjectContext
    @EnvironmentObject private var coreDataStack: CoreDataStack
    @EnvironmentObject private var cloudKitService: CloudKitService
    @EnvironmentObject private var preferencesManager: PreferencesManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.openWindow) private var openWindow
    var triggerMonitor: TriggerMonitorService?

    @State private var selectedItem: SidebarSelection = .allPrompts
    @State private var showingAddPrompt = false
    @State private var showingAddCategory = false
    @State private var editingCategory: NSManagedObject?
    @State private var showingOnboarding = false
    @State private var showingUpgradePrompt = false
    
    @StateObject private var importExportService: DataExportImportService
    
    @FetchRequest private var categories: FetchedResults<NSManagedObject>
    @FetchRequest private var allPrompts: FetchedResults<NSManagedObject>
    
    private let selectedItemKey = "PromptBind.SelectedSidebarItem"
    
    init(viewContext: NSManagedObjectContext, triggerMonitor: TriggerMonitorService?, cloudKitService: CloudKitService) {
        self.viewContext = viewContext
        self.triggerMonitor = triggerMonitor
        
        self._importExportService = StateObject(wrappedValue: DataExportImportService(viewContext: viewContext))
        
        let categoryRequest = NSFetchRequest<NSManagedObject>(entityName: "Category")
        categoryRequest.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true), NSSortDescriptor(key: "name", ascending: true)]
        _categories = FetchRequest(fetchRequest: categoryRequest)
        
        let promptRequest = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
        promptRequest.sortDescriptors = [NSSortDescriptor(key: "trigger", ascending: true)]
        _allPrompts = FetchRequest(fetchRequest: promptRequest)
    }
    
    var body: some View {
        // Breaking the view into computed properties to aid the compiler.
        mainView
            .onAppear(perform: setupView)
            .onChange(of: selectedItem, handleSelectionChange)
            .onChange(of: allPrompts.count) { oldCount, newCount in
                print("ContentView: Prompt count changed from \(oldCount) to \(newCount)")
                subscriptionManager.updatePromptCount(newCount)
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave), perform: handleContextSave)
            .onReceive(NotificationCenter.default.publisher(for: .exportData)) { _ in importExportService.exportData() }
            .onReceive(NotificationCenter.default.publisher(for: .importData)) { _ in 
                // Check if user has Pro access for import
                if subscriptionManager.hasProAccess() {
                    importExportService.importData()
                } else {
                    showingUpgradePrompt = true
                }
            }
            .sheet(isPresented: $showingAddPrompt) {
                PromptSheet(
                    viewContext: viewContext,
                    selectedCategory: selectedCategory,
                    categories: Array(categories)
                )
            }
            .sheet(isPresented: $showingAddCategory) {
                // Use the new, unified CategorySheet for adding.
                CategorySheet(
                    viewContext: viewContext,
                    category: nil,
                    existingCategories: Array(categories)
                )
            }
            .sheet(item: $editingCategory) { category in
                // Use the new, unified CategorySheet for editing.
                CategorySheet(
                    viewContext: viewContext,
                    category: category,
                    existingCategories: Array(categories)
                )
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingView {
                    // This completion block is called when the user finishes onboarding.
                    preferencesManager.hasCompletedOnboarding = true
                    showingOnboarding = false
                }
            }
            .sheet(isPresented: $showingUpgradePrompt) {
                UpgradePromptView()
            }
            .alert("Import/Export Status", isPresented: .constant(importExportService.lastError != nil || importExportService.successMessage != nil)) {
                Button("OK") {
                    importExportService.lastError = nil
                    importExportService.successMessage = nil
                }
            } message: {
                if let error = importExportService.lastError {
                    Text(error.localizedDescription)
                } else if let success = importExportService.successMessage {
                    Text(success)
                }
            }
    }
    
    // MARK: - View Components
    
    private var mainView: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            detailView
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: {
                    openWindow(id: "settings")
                }) {
                    Label("Settings", systemImage: "gear")
                }
                .help("Settings")
                
                #if DEBUG
                Button("Debug: Refresh Count") {
                    subscriptionManager.refreshPromptCount()
                }
                .help("Refresh subscription count")
                #endif
            }
        }
    }
    
    private var sidebarView: some View {
        List(selection: $selectedItem) {
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
            
            Section {
                ForEach(categories, id: \.objectID) { category in
                    SidebarCategoryRowView(
                        category: category,
                        isSelected: selectedItem == .category(category.objectID),
                        onEdit: { editingCategory = category }
                    )
                    .tag(SidebarSelection.category(category.objectID))
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .listRowSeparator(.hidden)
                }
                
                addCategoryButton
            } header: {
                Text("Categories")
                    .font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary).textCase(.uppercase)
                    .padding(.horizontal, 8).padding(.top, 16).padding(.bottom, 4)
            }
            
            #if DEBUG
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Debug Info:")
                        .font(.caption)
                        .fontWeight(.bold)
                    Text("Status: \(subscriptionManager.subscriptionStatus.displayName)")
                        .font(.caption)
                    Text("Count: \(subscriptionManager.promptCount)")
                        .font(.caption)
                    Text("Can Create: \(subscriptionManager.canCreatePrompt() ? "Yes" : "No")")
                        .font(.caption)
                        .foregroundColor(subscriptionManager.canCreatePrompt() ? .green : .red)
                    Text("At Limit: \(subscriptionManager.isAtFreeLimit() ? "Yes" : "No")")
                        .font(.caption)
                        .foregroundColor(subscriptionManager.isAtFreeLimit() ? .red : .green)
                    Text("Logic: \(subscriptionManager.promptCount) < 5 = \(subscriptionManager.promptCount < 5)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            } header: {
                Text("Subscription Debug")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            #endif
        }
        .listStyle(.sidebar)
        .navigationTitle("PromptBind")
        .scrollContentBackground(.hidden)
        .focusedSceneValue(\.selectedSidebarItem, $selectedItem)
        .onKeyPress(.upArrow) { navigateUp(); return .handled }
        .onKeyPress(.downArrow) { navigateDown(); return .handled }
    }
    
    private var addCategoryButton: some View {
        Button(action: { showingAddCategory = true }) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle").foregroundColor(.blue).frame(width: 18, height: 18).font(.system(size: 14, weight: .medium))
                Text("Add Category").font(.body).foregroundColor(.blue)
                Spacer()
            }
            .padding(.vertical, 4).padding(.horizontal, 8).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedItem {
        case .allPrompts:
            AllPromptsView(
                viewContext: viewContext,
                categories: Array(categories)
            )
        case .category(let categoryID):
            if let category = categories.first(where: { $0.objectID == categoryID }) {
                PromptsListView(
                    category: category,
                    viewContext: viewContext,
                    categories: Array(categories)
                )
            } else {
                CategoryNotFoundView(onSelectAllPrompts: { selectedItem = .allPrompts })
            }
        }
    }
    
    // MARK: - Helper Properties
    private var selectedCategory: NSManagedObject? {
        if case .category(let categoryID) = selectedItem {
            return categories.first { $0.objectID == categoryID }
        }
        return nil
    }
    
    // MARK: - Logic & Handlers
    
    private func setupView() {
        // Check for onboarding
        if !preferencesManager.hasCompletedOnboarding {
            showingOnboarding = true
        }
        
        restoreSelectedItem()
        
        // Ensure subscription manager has correct count after view appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            subscriptionManager.refreshPromptCount()
        }
    }
    
    private func handleSelectionChange(from oldValue: SidebarSelection, to newValue: SidebarSelection) {
        saveSelectedItem(newValue)
        print("ContentView: Selection changed to \(newValue)")
    }
    
    private func handleContextSave(_ notification: Notification) {
        triggerMonitor?.loadAllPrompts()
        validateCurrentSelection()
        
        // Update subscription manager after Core Data saves
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            subscriptionManager.refreshPromptCount()
        }
    }
    
    private func saveSelectedItem(_ item: SidebarSelection) {
        let key = "PromptBind.SelectedSidebarItem"
        switch item {
        case .allPrompts:
            UserDefaults.standard.set("allPrompts", forKey: key)
        case .category(let objectID):
            UserDefaults.standard.set("category:\(objectID.uriRepresentation().absoluteString)", forKey: key)
        }
    }
    
    private func restoreSelectedItem() {
        guard let savedString = UserDefaults.standard.string(forKey: selectedItemKey) else { return }
        if savedString == "allPrompts" {
            selectedItem = .allPrompts
        } else if savedString.hasPrefix("category:"),
                  let url = URL(string: String(savedString.dropFirst("category:".count))),
                  let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
                  categories.contains(where: { $0.objectID == objectID }) {
            selectedItem = .category(objectID)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedItemKey)
        }
    }
    
    private func validateCurrentSelection() {
        if case .category(let objectID) = selectedItem, !categories.contains(where: { $0.objectID == objectID }) {
            print("ContentView: Selected category no longer exists, switching to All Prompts")
            selectedItem = .allPrompts
        }
    }
    
    // MARK: - Keyboard Navigation
    
    private func navigateUp() {
        if case .category(let objectID) = selectedItem, let currentIndex = categories.firstIndex(where: { $0.objectID == objectID }) {
            if currentIndex > 0 {
                selectedItem = .category(categories[currentIndex - 1].objectID)
            } else {
                selectedItem = .allPrompts
            }
        }
    }
    
    private func navigateDown() {
        switch selectedItem {
        case .allPrompts:
            if let firstCategory = categories.first {
                selectedItem = .category(firstCategory.objectID)
            }
        case .category(let objectID):
            if let currentIndex = categories.firstIndex(where: { $0.objectID == objectID }), currentIndex < categories.count - 1 {
                selectedItem = .category(categories[currentIndex + 1].objectID)
            }
        }
    }
}

// MARK: - Subviews

/// List of prompts for a specific category
struct PromptsListView: View {
    let category: NSManagedObject
    let viewContext: NSManagedObjectContext
    let categories: [NSManagedObject]
    
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var showingAddPrompt = false
    @State private var editingPrompt: NSManagedObject?
    @State private var showingUpgradePrompt = false
    
    @FetchRequest private var prompts: FetchedResults<NSManagedObject>
    
    init(category: NSManagedObject, viewContext: NSManagedObjectContext, categories: [NSManagedObject]) {
        self.category = category
        self.viewContext = viewContext
        self.categories = categories
        
        let request = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
        request.predicate = NSPredicate(format: "category == %@", category)
        request.sortDescriptors = [NSSortDescriptor(key: "trigger", ascending: true)]
        _prompts = FetchRequest(fetchRequest: request)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CategoryHeaderView(
                icon: "folder.fill",
                iconColor: .orange,
                title: category.categoryName,
                count: prompts.count,
                onAddPrompt: { 
                    if subscriptionManager.canCreatePrompt() {
                        showingAddPrompt = true
                    } else {
                        showingUpgradePrompt = true
                    }
                }
            )
            Divider()
            content
        }
        .sheet(isPresented: $showingAddPrompt) {
            PromptSheet(viewContext: viewContext, selectedCategory: category, categories: categories)
        }
        .sheet(isPresented: $showingUpgradePrompt) {
            UpgradePromptView()
        }
        .background(
            ManagedObjectSheetBinding(item: $editingPrompt) { prompt in
                PromptSheet(viewContext: viewContext, prompt: prompt, categories: categories)
            }
        )
    }
    
    @ViewBuilder
    private var content: some View {
        if prompts.isEmpty {
            EmptyStateView(
                icon: "text.cursor",
                title: "No prompts in this category",
                subtitle: "Add your first prompt to get started",
                buttonTitle: subscriptionManager.canCreatePrompt() ? "Add Prompt" : "Upgrade to Add Prompts",
                onButtonTap: { 
                    if subscriptionManager.canCreatePrompt() {
                        showingAddPrompt = true
                    } else {
                        showingUpgradePrompt = true
                    }
                }
            )
        } else {
            PromptsListContentView(prompts: Array(prompts)) { prompt in
                editingPrompt = prompt
            }
        }
    }
}

/// List showing all prompts regardless of category
struct AllPromptsView: View {
    let viewContext: NSManagedObjectContext
    let categories: [NSManagedObject]
    
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var showingAddPrompt = false
    @State private var editingPrompt: NSManagedObject?
    @State private var showingUpgradePrompt = false
    
    @FetchRequest private var allPrompts: FetchedResults<NSManagedObject>
    
    init(viewContext: NSManagedObjectContext, categories: [NSManagedObject]) {
        self.viewContext = viewContext
        self.categories = categories
        
        let request = NSFetchRequest<NSManagedObject>(entityName: "Prompt")
        request.sortDescriptors = [NSSortDescriptor(key: "trigger", ascending: true)]
        _allPrompts = FetchRequest(fetchRequest: request)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CategoryHeaderView(
                icon: "text.cursor",
                iconColor: .blue,
                title: "All Prompts",
                count: allPrompts.count,
                onAddPrompt: { 
                    if subscriptionManager.canCreatePrompt() {
                        showingAddPrompt = true
                    } else {
                        showingUpgradePrompt = true
                    }
                }
            )
            Divider()
            content
        }
        .sheet(isPresented: $showingAddPrompt) {
            PromptSheet(viewContext: viewContext, selectedCategory: nil, categories: categories)
        }
        .sheet(isPresented: $showingUpgradePrompt) {
            UpgradePromptView()
        }
        .background(
            ManagedObjectSheetBinding(item: $editingPrompt) { prompt in
                PromptSheet(viewContext: viewContext, prompt: prompt, categories: categories)
            }
        )
    }
    
    @ViewBuilder
    private var content: some View {
        if allPrompts.isEmpty {
            EmptyStateView(
                icon: "text.cursor",
                title: "No prompts yet",
                subtitle: "Create your first prompt to get started",
                buttonTitle: subscriptionManager.canCreatePrompt() ? "Add Prompt" : "Upgrade to Add Prompts",
                onButtonTap: { 
                    if subscriptionManager.canCreatePrompt() {
                        showingAddPrompt = true
                    } else {
                        showingUpgradePrompt = true
                    }
                }
            )
        } else {
            AllPromptsListContentView(prompts: Array(allPrompts)) { prompt in
                editingPrompt = prompt
            }
        }
    }
}

// MARK: - Reusable UI Components

struct PromptRowView: View {
    let prompt: NSManagedObject
    let onEdit: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(prompt.displayName).font(.system(size: 15, weight: .medium)).foregroundColor(.primary)
                Text(prompt.promptExpansion.isEmpty ? "No content" : prompt.promptExpansion).font(.system(size: 13)).foregroundColor(.secondary).lineLimit(1).truncationMode(.tail)
            }
            Spacer()
            HStack(spacing: 8) {
                if !prompt.promptEnabled {
                    Image(systemName: "pause.circle.fill").foregroundColor(.orange).font(.system(size: 14)).help("Disabled")
                }
                Button(action: onEdit) {
                    Image(systemName: "pencil").foregroundColor(.blue).font(.system(size: 14))
                }
                .buttonStyle(.plain).help("Edit prompt")
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 16).background(Color.clear).contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
    }
}

struct SidebarRowView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let count: Int
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(iconColor).frame(width: 18, height: 18).font(.system(size: 14, weight: .medium))
            Text(title).font(.body).fontWeight(isSelected ? .medium : .regular)
            Spacer()
            Text("\(count)").font(.caption).fontWeight(.medium).foregroundColor(isSelected ? .white : .secondary).padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.2)))
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear))
        .contentShape(Rectangle())
    }
}

struct SidebarCategoryRowView: View {
    let category: NSManagedObject
    let isSelected: Bool
    let onEdit: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill").foregroundColor(.orange).frame(width: 18, height: 18).font(.system(size: 14, weight: .medium))
            Text(category.categoryName).font(.body).fontWeight(isSelected ? .medium : .regular)
            Spacer()
            if isHovering || isSelected {
                Button(action: onEdit) {
                    Image(systemName: "pencil").font(.system(size: 12)).foregroundColor(.secondary)
                }
                .buttonStyle(.plain).help("Edit category")
            }
            Text("\(category.categoryPrompts.count)").font(.caption).fontWeight(.medium).foregroundColor(isSelected ? .white : .secondary).padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.2)))
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear))
        .contentShape(Rectangle()).onHover { isHovering = $0 }
    }
}

struct CategoryNotFoundView: View {
    let onSelectAllPrompts: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.questionmark").font(.system(size: 48)).foregroundColor(.orange)
            VStack(spacing: 8) {
                Text("Category Not Found").font(.headline)
                Text("The selected category might have been deleted.").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            }
            Button("View All Prompts", action: onSelectAllPrompts).buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(.controlBackgroundColor).opacity(0.5))
    }
}

struct CategoryHeaderView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let count: Int
    let onAddPrompt: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundColor(iconColor).font(.title2)
                Text(title).font(.largeTitle).fontWeight(.bold)
                Spacer()
                Button(action: onAddPrompt) {
                    Image(systemName: "plus").font(.title2)
                }
                .buttonStyle(.plain).help("Add prompt")
            }
            Text("\(count) prompt\(count == 1 ? "" : "s")").font(.subheadline).foregroundColor(.secondary)
        }
        .padding().background(Color(.controlBackgroundColor))
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    let buttonTitle: String
    let onButtonTap: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 48)).foregroundColor(.secondary)
            Text(title).font(.headline).foregroundColor(.secondary)
            Text(subtitle).font(.subheadline).foregroundColor(.secondary)
            Button(buttonTitle, action: onButtonTap).buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(.controlBackgroundColor).opacity(0.5))
    }
}

struct PromptsListContentView: View {
    let prompts: [NSManagedObject]
    let onEdit: (NSManagedObject) -> Void
    
    var body: some View {
        List(prompts, id: \.objectID) { prompt in
            PromptRowView(prompt: prompt) { onEdit(prompt) }
            .listRowSeparator(.visible).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
        }
        .listStyle(.plain).background(Color(.controlBackgroundColor))
    }
}

struct AllPromptsListContentView: View {
    let prompts: [NSManagedObject]
    let onEdit: (NSManagedObject) -> Void
    
    var body: some View {
        List(prompts, id: \.objectID) { prompt in
            VStack(alignment: .leading, spacing: 0) {
                PromptRowView(prompt: prompt) { onEdit(prompt) }
                if let category = prompt.promptCategory {
                    HStack {
                        Image(systemName: "folder").font(.system(size: 11)).foregroundColor(.secondary)
                        Text(category.categoryName).font(.system(size: 11)).foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.bottom, 8)
                }
            }
            .listRowSeparator(.visible).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
        }
        .listStyle(.plain).background(Color(.controlBackgroundColor))
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
    }
}