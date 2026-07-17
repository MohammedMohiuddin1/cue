//
//  SplashWindow.swift
//  cluelyopen
//
//  Launch splash for Cue. A borderless, floating window that plays a short
//  brand animation — the aperture-eye mark draws in, the focus dot pulses,
//  the "Cue" wordmark reveals — then fades out and hands off to the overlay.
//
//  The mark is drawn in SwiftUI (not a bitmap) so it can be stroke-animated
//  and stays crisp at any scale.
//

import AppKit
import SwiftUI

// MARK: - Palette (shared Cue design tokens)

enum Cue {
    static let base    = Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0F/255)
    static let panel   = Color(red: 0x12/255, green: 0x12/255, blue: 0x1A/255)
    static let accent  = Color(red: 0x6E/255, green: 0x56/255, blue: 0xF7/255) // electric indigo
    static let accentHi = Color(red: 0xA7/255, green: 0x8B/255, blue: 0xFA/255) // lighter indigo
    static let text    = Color(red: 0xE8/255, green: 0xE8/255, blue: 0xF0/255)
    static let muted   = Color(red: 0x6B/255, green: 0x6B/255, blue: 0x7B/255)

    /// The indigo stroke gradient used on the aperture mark everywhere.
    static let markGradient = LinearGradient(
        colors: [accentHi, accent],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Aperture-eye shape (two arcs meeting at sharp points)

/// The Cue mark: a lens/almond outline formed by an upper and lower arc.
/// Drawn as a single continuous path so `.trim` animates it as one stroke.
///
/// `openness` drives a blink: 1 = fully open eye, 0 = closed to a flat line.
/// It's an animatable property, so `withAnimation` tweens the lids shut and
/// back open smoothly.
struct ApertureShape: Shape {
    var openness: CGFloat = 1

    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let midY = rect.midY
        let left = CGPoint(x: rect.minX, y: midY)
        let right = CGPoint(x: rect.maxX, y: midY)
        // Curve depth scales with openness — 0 collapses both arcs onto the
        // centre line (a closed lid), 1 is the full lens.
        let bow = rect.height * 0.5 * openness
        // Upper arc: left → right, bowing up.
        p.move(to: left)
        p.addQuadCurve(to: right,
                       control: CGPoint(x: rect.midX, y: midY - bow))
        // Lower arc: right → left, bowing down. Together they form the lens.
        p.addQuadCurve(to: left,
                       control: CGPoint(x: rect.midX, y: midY + bow))
        return p
    }
}

// MARK: - Splash view

struct SplashView: View {
    var onFinished: () -> Void

    @State private var drawProgress: CGFloat = 0   // aperture stroke 0→1
    @State private var openness: CGFloat = 1        // 1 open, 0 blinked shut
    @State private var dotScale: CGFloat = 0.2      // focus dot pop
    @State private var dotOpacity: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var wordmarkOpacity: Double = 0
    @State private var wordmarkOffset: CGFloat = 8
    @State private var rootOpacity: Double = 1

    private let markSize: CGFloat = 120

    var body: some View {
        ZStack {
            // Dark glass backdrop with a faint indigo bloom, matching the icon.
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Cue.base)
                .overlay(
                    RadialGradient(
                        colors: [Cue.accent.opacity(0.18), .clear],
                        center: .center, startRadius: 2, endRadius: 220)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )

            VStack(spacing: 26) {
                ZStack {
                    // Soft glow behind the mark.
                    ApertureShape(openness: openness)
                        .stroke(Cue.accentHi, lineWidth: 10)
                        .frame(width: markSize, height: markSize * 0.62)
                        .blur(radius: 14)
                        .opacity(glowOpacity * 0.6)

                    // The aperture outline, stroke-drawn, then blinks.
                    ApertureShape(openness: openness)
                        .trim(from: 0, to: drawProgress)
                        .stroke(Cue.markGradient,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .frame(width: markSize, height: markSize * 0.62)

                    // Focus dot (the "cue"), pops and settles with a glow.
                    // Hidden while the lid is closed so the blink reads cleanly.
                    Circle()
                        .fill(Cue.markGradient)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().fill(Cue.accentHi).frame(width: 26, height: 26).blur(radius: 8).opacity(0.7))
                        .scaleEffect(dotScale)
                        .opacity(dotOpacity * Double(max(0, (openness - 0.35) / 0.65)))
                }
                .frame(height: markSize * 0.62)

                Text("Cue")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(Cue.text)
                    .opacity(wordmarkOpacity)
                    .offset(y: wordmarkOffset)
            }
        }
        .frame(width: 300, height: 300)
        .opacity(rootOpacity)
        .onAppear(perform: runSequence)
    }

    /// Choreographed launch animation, then fade-out + handoff.
    private func runSequence() {
        // 1. Aperture strokes in.
        withAnimation(.easeInOut(duration: 0.7)) {
            drawProgress = 1
            glowOpacity = 1
        }
        // 2. Focus dot pops in as the outline completes.
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.55)) {
            dotScale = 1
            dotOpacity = 1
        }
        // 3. Blink — the eye closes and reopens once it's fully formed.
        withAnimation(.easeInOut(duration: 0.14).delay(1.15)) { openness = 0 }
        withAnimation(.easeInOut(duration: 0.18).delay(1.29)) { openness = 1 }
        // 4. Wordmark reveals just after the blink.
        withAnimation(.easeOut(duration: 0.5).delay(1.55)) {
            wordmarkOpacity = 1
            wordmarkOffset = 0
        }
        // 5. Hold, then fade the whole splash out and hand off.
        withAnimation(.easeIn(duration: 0.45).delay(2.5)) {
            rootOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            onFinished()
        }
    }
}

// MARK: - Window controller

final class SplashWindowController {
    private var window: NSWindow?

    /// Show the splash centred on the main screen. Calls `completion` after the
    /// animation finishes and the window has closed.
    func show(completion: @escaping () -> Void) {
        let root = SplashView { [weak self] in
            self?.close()
            completion()
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.contentView = NSHostingView(rootView: root)
        w.center()
        w.orderFrontRegardless()
        window = w
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
    }
}
