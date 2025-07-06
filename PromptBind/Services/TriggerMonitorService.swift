import AppKit
import SwiftData
import Combine

class TriggerMonitorService: ObservableObject {
    @Published private(set) var prompts: [Prompt] = []
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    private var currentBuffer: [String] = []
    private let maxBufferLength = 50
    
    private var modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadAllPrompts()
    }
    
    func loadAllPrompts() {
        do {
            let descriptor = FetchDescriptor<Prompt>()
            self.prompts = try modelContext.fetch(descriptor)
            print("TriggerMonitor loaded \(self.prompts.count) prompts")
        } catch {
            print("Failed to fetch prompts: \(error)")
        }
    }
    
    @MainActor
    func updatePrompts(_ newPrompts: [Prompt]) {
        loadAllPrompts()
    }
    
    nonisolated func startMonitoring() {
        guard AXIsProcessTrusted() else {
            print("Accessibility permissions not granted")
            return
        }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
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
                print("TriggerMonitor started")
            }
        }
    }
    
    nonisolated func stopMonitoring() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        currentBuffer = []
    }
    
    nonisolated private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .keyDown,
           let nsEvent = NSEvent(cgEvent: event),
           let chars = nsEvent.charactersIgnoringModifiers {
            
            currentBuffer.append(chars)
            if currentBuffer.count > maxBufferLength {
                currentBuffer.removeFirst()
            }
            
            let currentText = currentBuffer.joined()
            
            for prompt in prompts where prompt.enabled {
                if currentText.hasSuffix(prompt.trigger) {
                    print("Trigger matched: \(prompt.trigger) -> \(prompt.expansion)")
                    deleteCharacters(count: prompt.trigger.count)
                    
                    insertText(prompt.expansion)
                    
                    currentBuffer = []
                    
                    return nil
                }
            }
        }
        
        return Unmanaged.passRetained(event)
    }
    
    nonisolated private func deleteCharacters(count: Int) {
        guard count > 0 else { return }
        
        let deleteKey = CGKeyCode(51)
        
        for _ in 0..<count {
            let deleteDown = CGEvent(keyboardEventSource: nil, virtualKey: deleteKey, keyDown: true)
            let deleteUp = CGEvent(keyboardEventSource: nil, virtualKey: deleteKey, keyDown: false)
            
            deleteDown?.post(tap: .cgSessionEventTap)
            deleteUp?.post(tap: .cgSessionEventTap)
        }
    }
    
    nonisolated private func insertText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        let cmdKeyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: true)
        let cmdKeyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: false)
        let vKeyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)
        let vKeyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
        
        cmdKeyDown?.flags = .maskCommand
        vKeyDown?.flags = .maskCommand
        
        cmdKeyDown?.post(tap: .cgSessionEventTap)
        vKeyDown?.post(tap: .cgSessionEventTap)
        vKeyUp?.post(tap: .cgSessionEventTap)
        cmdKeyUp?.post(tap: .cgSessionEventTap)
    }
    
    deinit {
        stopMonitoring()
    }
}