import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Prompt.trigger) private var prompts: [Prompt]
    
    @State private var showingAddSheet = false
    @StateObject private var triggerMonitor: TriggerMonitorService
    
    init(modelContext: ModelContext) {
        _triggerMonitor = StateObject(wrappedValue: TriggerMonitorService(modelContext: modelContext))
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(prompts) { prompt in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(prompt.trigger)
                                .font(.headline)
                            Text(prompt.expansion)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { prompt.enabled },
                            set: { newValue in
                                prompt.enabled = newValue
                            }
                        ))
                    }
                }
                .onDelete(perform: deletePrompts)
            }
            .navigationTitle("Text Snippets")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddSheet = true }) {
                        Label("Add Snippet", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddPromptView()
        }
        .onAppear {
            triggerMonitor.startMonitoring()
        }
        .onDisappear {
            triggerMonitor.stopMonitoring()
        }
    }
    
    private func deletePrompts(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(prompts[index])
            }
        }
    }
}

struct AddPromptView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    
    @State private var trigger = ""
    @State private var expansion = ""
    
    var body: some View {
        NavigationView {
            Form {
                TextField("Trigger (e.g. ;hello)", text: $trigger)
                TextField("Expansion", text: $expansion)
            }
            .navigationTitle("Add Snippet")
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() },
                trailing: Button("Save") {
                    addPrompt()
                    dismiss()
                }
                .disabled(trigger.isEmpty || expansion.isEmpty)
            )
        }
    }
    
    private func addPrompt() {
        let prompt = Prompt(trigger: trigger, expansion: expansion)
        modelContext.insert(prompt)
    }
}

#Preview {
    ContentView(modelContext: try! ModelContainer(for: Prompt.self).mainContext)
        .modelContainer(for: Prompt.self, inMemory: true)
}