import Foundation
import AppKit // For NSEvent, CGEvent
import Combine
import Carbon.HIToolbox // Specifically for TIS types

class TriggerMonitorService: TriggerMonitoring {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let triggerSubject = PassthroughSubject<TriggerEvent, Never>()
    var triggerPublisher: AnyPublisher<TriggerEvent, Never> {
        triggerSubject.eraseToAnyPublisher()
    }

    private var currentInputBuffer: [String] = []
    private let maxBufferLength: Int
    private var activeTriggers: [String] = []

    private var currentLayout: TISInputSource?

    init(maxBufferLength: Int = 50) {
        self.maxBufferLength = maxBufferLength
        self.currentLayout = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    func startMonitoring(triggers: [String]) {
        guard !triggers.isEmpty else {
            print("TriggerMonitorService: No triggers provided. Monitoring not started.")
            return
        }

        self.activeTriggers = triggers.sorted { $0.count > $1.count } 
        self.currentInputBuffer = []

        guard AXIsProcessTrusted() else {
            print("TriggerMonitorService: Accessibility permissions not granted. Cannot start monitoring.")
            return
        }

        if eventTap == nil {
            let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
            
            eventTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                    if let refcon = refcon {
                        let service = Unmanaged<TriggerMonitorService>.fromOpaque(refcon).takeUnretainedValue()
                        return service.handleEvent(proxy: proxy, type: type, event: event)
                    }
                    return Unmanaged.passRetained(event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )

            if let eventTap = eventTap {
                runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
                if let runLoopSource = runLoopSource {
                    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                    print("TriggerMonitorService: Event tap started with \(triggers.count) triggers.")
                } else {
                    print("TriggerMonitorService: Failed to create run loop source.")
                    self.eventTap = nil
                }
            } else {
                print("TriggerMonitorService: Failed to create event tap. Ensure Accessibility permissions are granted.")
            }
        }
    }

    func stopMonitoring() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let runLoopSource = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
                self.runLoopSource = nil
            }
            self.eventTap = nil
            
            currentInputBuffer = []
            activeTriggers = []
            print("TriggerMonitorService: Event tap stopped.")
        }
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }

        if let nsEvent = NSEvent(cgEvent: event) {
            if let chars = nsEvent.charactersIgnoringModifiers, !chars.isEmpty {
                let char = String(chars.first!) 
                
                currentInputBuffer.append(char)
                if currentInputBuffer.count > maxBufferLength {
                    currentInputBuffer.removeFirst()
                }
                
                checkForTriggers()
            }
        }
        
        return Unmanaged.passRetained(event)
    }

    private func checkForTriggers() {
        guard !currentInputBuffer.isEmpty, !activeTriggers.isEmpty else { return }

        let currentSequence = currentInputBuffer.joined()

        for trigger in activeTriggers {
            if currentSequence.hasSuffix(trigger) {
                print("Trigger detected: \(trigger)")
                triggerSubject.send(TriggerEvent(trigger: trigger))
                currentInputBuffer = [] 
                break 
            }
        }
    }

    deinit {
        stopMonitoring()
    }
}