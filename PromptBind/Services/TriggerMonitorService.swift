import AppKit
import SwiftData
import Combine

class TriggerMonitorService: ObservableObject {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    private var currentBuffer: [String] = []
    private let maxBufferLength = 50
    
    private let modelContext: ModelContext
    @Query private var prompts: [Prompt]
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func startMonitoring() {
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
    
    func stopMonitoring() {
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
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .keyDown,
           let nsEvent = NSEvent(cgEvent: event),
           let chars = nsEvent.charactersIgnoringModifiers {
            
            currentBuffer.append(chars)
            if currentBuffer.count > maxBufferLength {
                currentBuffer.removeFirst()
            }
            
            let currentText = currentBuffer.joined()
            
            // Check for triggers
            for prompt in prompts where prompt.enabled {
                if currentText.hasSuffix(prompt.trigger) {
                    // Delete the trigger text
                    deleteCharacters(count: prompt.trigger.count)
                    
                    // Insert the expansion
                    insertText(prompt.expansion)
                    
                    // Clear buffer after expansion
                    currentBuffer = []
                    
                    // Don't pass the last keystroke through
                    return nil
                }
            }
        }
        
        return Unmanaged.passRetained(event)
    }
    
    private func deleteCharacters(count: Int) {
        guard count > 0 else { return }
        
        let deleteKey = CGKeyCode(51) // Delete key
        
        for _ in 0..<count {
            let deleteDown = CGEvent(keyboardEventSource: nil, virtualKey: deleteKey, keyDown: true)
            let deleteUp = CGEvent(keyboardEventSource: nil, virtualKey: deleteKey, keyDown: false)
            
            deleteDown?.post(tap: .cgSessionEventTap)
            deleteUp?.post(tap: .cgSessionEventTap)
        }
    }
    
    private func insertText(_ text: String) {
        // Use pasteboard for expansion insertion
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Simulate Cmd+V
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