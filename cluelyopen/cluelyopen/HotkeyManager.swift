//
//  HotkeyManager.swift
//  cluelyopen
//
//  Global keyboard shortcuts that work even when another app (e.g. Zoom) is
//  focused. Uses a CGEvent tap — more reliable than NSEvent global monitors for
//  modifier combos. Requires the Accessibility permission.
//

import AppKit
import CoreGraphics

final class HotkeyManager {
    struct Handlers {
        var toggleOverlay: () -> Void = {}
        var answer: () -> Void = {}
        var move: (_ dx: CGFloat, _ dy: CGFloat) -> Void = { _, _ in }
    }

    private let handlers: Handlers
    private let moveStep: CGFloat = 40
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(handlers: Handlers) { self.handlers = handlers }

    func start() {
        let mask = (1 << CGEventType.keyDown.rawValue)

        // `passRetained(self)` bridges self into the C callback via `userInfo`.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                if manager.handle(type: type, event: event) {
                    return nil   // consume the event
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            NSLog("OpenCluely: failed to create event tap (Accessibility permission missing?)")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.runLoopSource = source
        NSLog("OpenCluely: event tap installed")
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    /// Returns true if the event was handled (and should be consumed).
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        // Re-enable if the system disabled our tap (e.g. after a timeout).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type == .keyDown else { return false }

        let flags = event.flags
        let cmd = flags.contains(.maskCommand)
        guard cmd else { return false }
        // Only plain ⌘ (no shift/opt/ctrl) to avoid clashing with system combos.
        let onlyCommand = !flags.contains(.maskShift)
            && !flags.contains(.maskAlternate)
            && !flags.contains(.maskControl)
        guard onlyCommand else { return false }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch keyCode {
        case 42:  DispatchQueue.main.async { self.handlers.toggleOverlay() }; return true   // \
        case 36, 76: DispatchQueue.main.async { self.handlers.answer() }; return true        // return / enter
        case 126: DispatchQueue.main.async { self.handlers.move(0, self.moveStep) }; return true   // up
        case 125: DispatchQueue.main.async { self.handlers.move(0, -self.moveStep) }; return true  // down
        case 123: DispatchQueue.main.async { self.handlers.move(-self.moveStep, 0) }; return true  // left
        case 124: DispatchQueue.main.async { self.handlers.move(self.moveStep, 0) }; return true   // right
        default: return false
        }
    }
}
