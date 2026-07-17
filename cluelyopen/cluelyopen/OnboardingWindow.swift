//
//  OnboardingWindow.swift
//  cluelyopen
//
//  First-run wizard for Cue: welcome → permissions → quick tour → ready.
//  Shown once (gated on a UserDefaults flag). Cue-branded, dark glass, with
//  the glowing aperture mark and animated step transitions.
//

import AppKit
import SwiftUI
import Combine

struct OnboardingView: View {
    let permissions: PermissionsManager
    var onFinish: () -> Void

    @State private var step = 0
    @State private var hasScreen = false
    @State private var hasAccess = false
    @State private var appeared = false
    // Re-check permission status on a timer while the wizard is open.
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let stepCount = 4

    var body: some View {
        ZStack {
            // Cue dark-glass backdrop with a faint indigo bloom.
            Cue.base.ignoresSafeArea()
            RadialGradient(colors: [Cue.accent.opacity(0.16), .clear],
                           center: .topLeading, startRadius: 4, endRadius: 620)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(36)
                    .id(step)   // drives the per-step transition
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)))

                footer
            }
        }
        .frame(width: 640, height: 500)
        .preferredColorScheme(.dark)
        .onReceive(ticker) { _ in
            hasScreen = permissions.hasScreenRecording
            hasAccess = permissions.hasAccessibility
        }
        .onAppear {
            hasScreen = permissions.hasScreenRecording
            hasAccess = permissions.hasAccessibility
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }

    // MARK: Footer (progress dots + nav)

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { advance(-1) }
                    .buttonStyle(.plain).foregroundStyle(Cue.muted)
            }
            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<stepCount, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? AnyShapeStyle(Cue.markGradient)
                                        : AnyShapeStyle(Cue.muted.opacity(0.35)))
                        .frame(width: i == step ? 20 : 7, height: 7)
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: step)
                }
            }
            Spacer()
            Button(step < stepCount - 1 ? "Continue" : "Get Started") {
                if step < stepCount - 1 { advance(1) } else { onFinish() }
            }
            .buttonStyle(CueButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(step == 1 && !hasScreen)   // must grant Screen Recording to pass
        }
        .padding(20)
        .background(.black.opacity(0.25))
    }

    private func advance(_ delta: Int) {
        withAnimation(.easeInOut(duration: 0.4)) {
            step = max(0, min(stepCount - 1, step + delta))
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0: welcomeStep
        case 1: permissionsStep
        case 2: tourStep
        default: readyStep
        }
    }

    // MARK: Steps

    private var welcomeStep: some View {
        VStack(spacing: 22) {
            AnimatedApertureMark(size: 96)
            Text("Welcome to Cue").font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(Cue.text)
            Text("A free, 100% local interview assistant. Live audio transcription, screen reading, and AI answers — all on your Mac. No accounts, no cloud, no keys.")
                .multilineTextAlignment(.center).foregroundStyle(Cue.muted)
                .frame(maxWidth: 460)
            Text("You'll need Ollama running with a model pulled (e.g. qwen2.5-coder:7b) — or bring your own cloud key later.")
                .font(.caption).foregroundStyle(Cue.muted.opacity(0.8))
                .multilineTextAlignment(.center)
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Grant permissions").font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(Cue.text)
            Text("Cue needs these macOS permissions. After clicking Grant, you may need to toggle it on in System Settings, then return here.")
                .font(.callout).foregroundStyle(Cue.muted)

            permissionCard(
                title: "Screen Recording",
                subtitle: "Required — captures meeting audio and reads your screen.",
                granted: hasScreen,
                grant: { permissions.requestScreenRecording(); permissions.openScreenRecordingSettings() }
            )
            permissionCard(
                title: "Accessibility",
                subtitle: "Optional — enables global keyboard shortcuts.",
                granted: hasAccess,
                grant: { permissions.requestAccessibility(); permissions.openAccessibilitySettings() }
            )

            if !hasScreen {
                Text("Screen Recording is required to continue. After enabling it, you may need to quit and relaunch Cue.")
                    .font(.caption).foregroundStyle(Color.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func permissionCard(title: String, subtitle: String, granted: Bool, grant: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color.green : Cue.muted).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Cue.text)
                Text(subtitle).font(.caption).foregroundStyle(Cue.muted)
            }
            Spacer()
            if !granted { Button("Grant", action: grant).buttonStyle(CueButtonStyle()) }
        }
        .padding(14)
        .background(Cue.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(granted ? Color.green.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1))
    }

    private var tourStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How it works").font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(Cue.text)
            tourRow("waveform", "Listen", "Capture meeting audio → live transcript → press ⌘↩ (or Send) for an answer.")
            tourRow("text.viewfinder", "Read Screen", "Answer a coding question that's visible on your screen.")
            tourRow("camera.viewfinder", "Screenshot", "Drag-select a region → solved by a vision model.")
            tourRow("paperclip", "Upload", "Add an image, PDF, or text file as context.")
            tourRow("eye", "Invisible", "Toggle to hide the overlay from screen-share (default: visible).")
            tourRow("slider.horizontal.3", "Settings", "Pick your model, choose a coding Mode, add your resume in Materials.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tourRow(_ icon: String, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .frame(width: 26, height: 26)
                .foregroundStyle(Cue.accentHi)
                .background(Cue.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout).bold().foregroundStyle(Cue.text)
                Text(desc).font(.caption).foregroundStyle(Cue.muted)
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: 20) {
            AnimatedApertureMark(size: 96)
            Text("You're all set").font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(Cue.text)
            Text("The overlay bar is on your screen, and Cue lives in your menu bar. Add your resume in Settings ▸ Materials for behavioral questions. Good luck!")
                .multilineTextAlignment(.center).foregroundStyle(Cue.muted)
                .frame(maxWidth: 460)
        }
    }
}

// MARK: - Animated aperture mark (welcome / ready)

/// The Cue aperture-eye, drawn on appear with a gentle stroke-in and a
/// slowly pulsing focus dot.
struct AnimatedApertureMark: View {
    var size: CGFloat = 96
    @State private var draw: CGFloat = 0
    @State private var pulse = false
    @State private var openness: CGFloat = 1
    // Blinks the eye every few seconds while the wizard is open.
    private let blinkTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            ApertureShape(openness: openness)
                .stroke(Cue.accentHi, lineWidth: 8)
                .frame(width: size, height: size * 0.62)
                .blur(radius: 12).opacity(0.5)

            ApertureShape(openness: openness)
                .trim(from: 0, to: draw)
                .stroke(Cue.markGradient,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size * 0.62)

            Circle()
                .fill(Cue.markGradient)
                .frame(width: size * 0.19, height: size * 0.19)
                .scaleEffect(pulse ? 1.12 : 0.92)
                .opacity(draw * Double(max(0, (openness - 0.35) / 0.65)))
        }
        .frame(height: size * 0.62)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7)) { draw = 1 }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(0.7)) {
                pulse = true
            }
            // First blink shortly after the mark forms.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { blink() }
        }
        .onReceive(blinkTimer) { _ in blink() }
    }

    private func blink() {
        withAnimation(.easeInOut(duration: 0.13)) { openness = 0 }
        withAnimation(.easeInOut(duration: 0.17).delay(0.13)) { openness = 1 }
    }
}

// MARK: - Cue button style

struct CueButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(Cue.text)
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(Cue.markGradient.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: 9))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

final class OnboardingWindowController {
    private var window: NSWindow?
    private let flagKey = "didCompleteOnboarding"

    var shouldShow: Bool { !UserDefaults.standard.bool(forKey: flagKey) }

    func show(permissions: PermissionsManager, onFinish: @escaping () -> Void) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let root = OnboardingView(permissions: permissions) { [weak self] in
            UserDefaults.standard.set(true, forKey: self?.flagKey ?? "didCompleteOnboarding")
            self?.window?.close()
            self?.window = nil
            NSApp.setActivationPolicy(.accessory)
            onFinish()
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Welcome to Cue"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: root)
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}
