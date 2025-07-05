import Foundation
import Combine

// Event payload for when a trigger is detected
struct TriggerEvent {
    let trigger: String
    // let range: NSRange // TRD mentioned NSRange, but for now, just the trigger string is simpler
                        // If we need the range for deletion, TriggerMonitorService could calculate it.
}

// Protocol for the trigger monitoring service
protocol TriggerMonitoring {
    var triggerPublisher: AnyPublisher<TriggerEvent, Never> { get }
    
    func startMonitoring(triggers: [String])
    func stopMonitoring()
}