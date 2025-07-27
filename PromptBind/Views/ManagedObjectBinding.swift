import SwiftUI
import CoreData

// Helper to make NSManagedObject work with SwiftUI sheets
extension NSManagedObject: Identifiable {
    public var id: NSManagedObjectID { objectID }
}

// Custom binding helper for NSManagedObject sheets
struct ManagedObjectSheetBinding<Content: View>: View {
    @Binding var item: NSManagedObject?
    let content: (NSManagedObject) -> Content
    
    var body: some View {
        EmptyView()
            .sheet(isPresented: Binding(
                get: { item != nil },
                set: { if !$0 { item = nil } }
            )) {
                if let item = item {
                    content(item)
                }
            }
    }
}