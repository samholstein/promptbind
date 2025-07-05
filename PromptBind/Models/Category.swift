import SwiftData
import Foundation

@Model
final class Category {
    var name: String
    var order: Int16 // For sorting categories

    // Relationship: A category can have many prompts
    @Relationship(inverse: \Prompt.category)
    var prompts: [Prompt]?
    
    init(name: String, order: Int16) {
        self.name = name
        self.order = order
    }
}