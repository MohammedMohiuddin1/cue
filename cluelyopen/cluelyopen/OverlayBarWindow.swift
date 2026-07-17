//
//  OverlayBarWindow.swift
//  cluelyopen
//
//  The floating, screen-capture-excluded panel that hosts the command bar.
//

import AppKit
import SwiftUI

/// A borderless floating panel.
/// `sharingType = .none` excludes it from default screen-share/recording capture
/// (see project docs on the macOS 15+ ScreenCaptureKit limitation — this is
/// honest-effort exclusion, not undefeatable invisibility).
final class OverlayBarWindow: NSPanel, NSWindowDelegate {
    /// Called whenever the user finishes resizing, so the size can be persisted.
    var onResize: ((NSSize) -> Void)?

    init(content: NSView) {
        super.init(
            contentRect: NSRect(x: 200, y: 200, width: 560, height: 120),
            // `.resizable` gives the panel drag-to-resize edges/corners.
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        // Keep the bar within sensible bounds while letting it grow to fit a
        // long conversation or shrink back to the compact command bar.
        minSize = NSSize(width: 420, height: 96)
        maxSize = NSSize(width: 1100, height: 900)
        // Default: VISIBLE to screen capture. The user turns on "invisible"
        // (capture-excluded) mode explicitly via the toolbar toggle.
        sharingType = .readOnly
        contentView = content
        delegate = self
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func windowDidEndLiveResize(_ notification: Notification) {
        onResize?(frame.size)
    }

    /// Apply a size, clamped to `minSize`/`maxSize`. AppKit only enforces those
    /// bounds for user drags, not for programmatic sizing, so a restored size
    /// from preferences goes through here to stay in range.
    func setClampedContentSize(_ size: NSSize) {
        setContentSize(NSSize(
            width: min(max(size.width, minSize.width), maxSize.width),
            height: min(max(size.height, minSize.height), maxSize.height)
        ))
    }

    /// Whether the panel is currently hidden from screen-share/recording.
    var isCaptureExcluded: Bool { sharingType == .none }

    /// Toggle capture exclusion. Returns the new state.
    @discardableResult
    func toggleCaptureExclusion() -> Bool {
        sharingType = (sharingType == .none) ? .readOnly : .none
        return isCaptureExcluded
    }
}
