//
//  HotkeyManager.swift
//  cluelyopen
//
//  Global keyboard shortcuts that work even when another app (e.g. Zoom) is
//  focused. Uses NSEvent global + local monitors. Global monitoring requires
//  the Accessibility permission (handled in onboarding).
//

import AppKit

final class HotkeyManager {
    struct Handlers {
        var toggleOverlay: () -> Void = {}
        var answer: () -> Void = {}
        var move: (_ dx: CGFloat, _ dy: CGFloat) -> Void = { _, _ in }
    }

    private var monitors: [Any] = []
    private let handlers: Handlers
    private let moveStep: CGFloat = 40

    init(handlers: Handlers) { self.handlers = handlers }

    func start() {
        // Global monitor: fires when other apps are focused (needs Accessibility).
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            self?.route(e)
        }) { monitors.append(g) }
        // Local monitor: fires when our own window is focused. Return nil to
        // swallow the event when we handle it.
        if let l = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            self?.route(e) == true ? nil : e
        }) { monitors.append(l) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    /// Handle a key event. Returns true if consumed.
    @discardableResult
    private func route(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return false }
        // Ignore if extra modifiers (shift/opt/ctrl) are held, to avoid clashes.
        let onlyCommand = flags.subtracting(.command).isEmpty

        switch event.keyCode {
        case 42 where onlyCommand:   // backslash
            handlers.toggleOverlay(); return true
        case 36 where onlyCommand,   // return
             76 where onlyCommand:   // keypad enter
            handlers.answer(); return true
        case 126 where onlyCommand:  handlers.move(0, moveStep); return true   // up
        case 125 where onlyCommand:  handlers.move(0, -moveStep); return true  // down
        case 123 where onlyCommand:  handlers.move(-moveStep, 0); return true  // left
        case 124 where onlyCommand:  handlers.move(moveStep, 0); return true   // right
        default: return false
        }
    }
}
