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
final class OverlayBarWindow: NSPanel {
    init(content: NSView) {
        super.init(
            contentRect: NSRect(x: 200, y: 200, width: 560, height: 120),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
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
        // Default: VISIBLE to screen capture. The user turns on "invisible"
        // (capture-excluded) mode explicitly via the toolbar toggle.
        sharingType = .readOnly
        contentView = content
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Whether the panel is currently hidden from screen-share/recording.
    var isCaptureExcluded: Bool { sharingType == .none }

    /// Toggle capture exclusion. Returns the new state.
    @discardableResult
    func toggleCaptureExclusion() -> Bool {
        sharingType = (sharingType == .none) ? .readOnly : .none
        return isCaptureExcluded
    }
}
