import SwiftData
import Foundation

@Model
final class Prompt {
    var trigger: String
    var expansion: String
    var enabled: Bool
    
    init(trigger: String, expansion: String, enabled: Bool = true) {
        self.trigger = trigger
        self.expansion = expansion
        self.enabled = enabled
    }
}