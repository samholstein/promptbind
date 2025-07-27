import SwiftUI
import CoreData

struct ContentView: View {
    let viewContext: NSManagedObjectContext
    @EnvironmentObject private var coreDataStack: CoreDataStack
    @EnvironmentObject private var cloudKitService: CloudKitService
    var triggerMonitor: TriggerMonitorService?
    
    @State private var showingSettingsSheet = false

    init(viewContext: NSManagedObjectContext, triggerMonitor: TriggerMonitorService?, cloudKitService: CloudKitService) {
        self.viewContext = viewContext
        self.triggerMonitor = triggerMonitor
    }
    
    var body: some View {
        NavigationSplitView {
            Text("Categories")
                .navigationTitle("Categories")
        } detail: {
            VStack {
                // CloudKit status bar
                Button(action: {
                    showingSettingsSheet = true
                }) {
                    HStack {
                        if coreDataStack.isCloudKitReady {
                            Image(systemName: "icloud")
                                .foregroundColor(.blue)
                            Text("Synced with iCloud")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "icloud.slash")
                                .foregroundColor(.orange)
                            Text(coreDataStack.cloudKitError ?? "Not signed into iCloud")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .background(coreDataStack.isCloudKitReady ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
                }
                .buttonStyle(.plain)
                .help("Click to open Settings")
                
                Text("All Prompts")
                    .font(.headline)
                    .padding(.top)
                
                Spacer()
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: {
                        showingSettingsSheet = true
                    }) {
                        Label("Settings", systemImage: "gear")
                    }
                    .help("Settings")
                    
                    Button(action: {
                        // Add prompt action - will implement later
                    }) {
                        Label("Add Prompt", systemImage: "plus")
                    }
                    .help("Add new prompt")
                }
            }
        }
        .sheet(isPresented: $showingSettingsSheet) {
            SettingsView()
                .environmentObject(cloudKitService)
                .environmentObject(coreDataStack)
        }
        .onAppear {
            print("ContentView: onAppear called")
            
            Task {
                await handleDefaultPrompts()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            showingSettingsSheet = true
        }
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
        // Create default category
        let uncategorizedCategory = NSEntityDescription.insertNewObject(forEntityName: "Category", into: viewContext)
        uncategorizedCategory.setValue("Uncategorized", forKey: "name")
        uncategorizedCategory.setValue(Int16(0), forKey: "order")
        uncategorizedCategory.setValue(UUID(), forKey: "id")
        
        let vibeCodingCategory = NSEntityDescription.insertNewObject(forEntityName: "Category", into: viewContext)
        vibeCodingCategory.setValue("Vibe Coding", forKey: "name")
        vibeCodingCategory.setValue(Int16(1), forKey: "order")
        vibeCodingCategory.setValue(UUID(), forKey: "id")
        
        // Create default prompts
        let defaultPrompts = [
            ("agentrules", "You are a disciplined AI coding assistant embedded in my development environment. You are not an autonomous agent; you are a collaborator under supervision. Follow the rules below at all times unless explicitly told otherwise.\n\nCore Rules:\n\t1.\tNo Autonomous Implementation\nDo not implement new features, refactorings, or architectural changes without explicit user approval.\n\n\t2.\tFrequent Check-Ins\nAfter each major step, change, or discovery (including test outcomes or roadblocks), stop and report back to me. Await feedback before continuing.\n\n\t3.\tRespect Feature Intentions\nDo not \"solve\" bugs or obstacles by eliminating or working around the intended feature. Instead, report the issue to me and wait for clarification or a decision from me on how to proceed.\n\n\t4.\tDo Not Modify the Plan Midstream\nDo not revise your project plan or execution strategy based on speculative insights or comments unless the I explicitly approves a plan modification.\n\n\t5.\tPre-Implementation Review\nBefore implementing a new feature or fix, write up a short technical implementation specification and review it with me. Proceed only once I approve both the what and the how.\n\n\t6.\tTesting Is a Stop Point\nWhen a test confirms a feature or bug fix is complete, pause and notify me so I can verify and optionally commit the change to git. Do not continue unprompted.\n\n\t7.\tClarity Over Creativity\nYour job is not to anticipate what I might want. Your job is to ask when in doubt and document clearly. Err on the side of caution.", vibeCodingCategory),
            ("itp ", "Go ahead and implement this plan.", vibeCodingCategory),
            ("revproj", "Please review this project and report to me your understanding of the functionality of this project at a high level. Do not modify anything.", vibeCodingCategory),
            ("tipp", "Please make a technical implementation plan with me and seek approval before proceeding. Do not include a timeline.", vibeCodingCategory)
        ]
        
        for (trigger, expansion, category) in defaultPrompts {
            let prompt = NSEntityDescription.insertNewObject(forEntityName: "Prompt", into: viewContext)
            prompt.setValue(UUID(), forKey: "id")
            prompt.setValue(trigger, forKey: "trigger")
            prompt.setValue(expansion, forKey: "expansion")
            prompt.setValue(true, forKey: "enabled")
            prompt.setValue(category, forKey: "category")
        }
        
        // Save to Core Data (and CloudKit automatically)
        do {
            try viewContext.save()
            print("ContentView: Default prompts saved successfully")
        } catch {
            print("ContentView: Error saving default prompts: \(error)")
        }
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