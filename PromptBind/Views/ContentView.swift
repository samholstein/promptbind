import SwiftUI
import CoreData

struct ContentView: View {
    let viewContext: NSManagedObjectContext
    @EnvironmentObject private var coreDataStack: CoreDataStack
    @EnvironmentObject private var cloudKitService: CloudKitService
    @EnvironmentObject private var windowManager: WindowManager
    var triggerMonitor: TriggerMonitorService?

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
                    windowManager.openSettingsWindow()
                }) {
                    HStack {
                        if coreDataStack.isCloudKitReady && coreDataStack.cloudKitError == nil {
                            Image(systemName: "icloud")
                                .foregroundColor(.blue)
                            Text("Synced with iCloud")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("A Core Data error occurred")
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
                    .background(Color.orange.opacity(0.1))
                }
                .buttonStyle(.plain)
                .help("Click to open Settings - Error: \(coreDataStack.cloudKitError ?? "Unknown error")")
                
                Text("All Prompts")
                    .font(.headline)
                    .padding(.top)
                
                Spacer()
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
                        // Add prompt action - will implement later
                    }) {
                        Label("Add Prompt", systemImage: "plus")
                    }
                    .help("Add new prompt")
                }
            }
        }
        .onAppear {
            print("ContentView: onAppear called")
            
            Task {
                await handleDefaultPrompts()
            }
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
        print("ContentView: Starting to add default prompts...")
        
        do {
            // Create default category
            let uncategorizedCategory = NSEntityDescription.insertNewObject(forEntityName: "Category", into: viewContext)
            uncategorizedCategory.setValue("Uncategorized", forKey: "name")
            uncategorizedCategory.setValue(Int16(0), forKey: "order")
            uncategorizedCategory.setValue(UUID(), forKey: "id")
            
            print("ContentView: Created Uncategorized category")
            
            // Create one simple test prompt
            let testPrompt = NSEntityDescription.insertNewObject(forEntityName: "Prompt", into: viewContext)
            testPrompt.setValue(UUID(), forKey: "id")
            testPrompt.setValue("test", forKey: "trigger")
            testPrompt.setValue("This is a test prompt", forKey: "expansion")
            testPrompt.setValue(true, forKey: "enabled")
            testPrompt.setValue(uncategorizedCategory, forKey: "category")
            
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