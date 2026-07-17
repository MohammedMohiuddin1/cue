//
//  OnboardingWindow.swift
//  cluelyopen
//
//  First-run wizard: welcome → permissions → quick tour → done.
//  Shown once (gated on a UserDefaults flag).
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
    // Re-check permission status on a timer while the wizard is open.
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)

            Divider()
            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                Text("\(step + 1) / 4").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(step < 3 ? "Continue" : "Get Started") {
                    if step < 3 { step += 1 } else { onFinish() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(step == 1 && !hasScreen)   // must grant Screen Recording to pass
            }
            .padding()
        }
        .frame(width: 640, height: 480)
        .onReceive(ticker) { _ in
            hasScreen = permissions.hasScreenRecording
            hasAccess = permissions.hasAccessibility
        }
        .onAppear {
            hasScreen = permissions.hasScreenRecording
            hasAccess = permissions.hasAccessibility
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

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles").font(.system(size: 48)).foregroundStyle(.blue)
            Text("Welcome to OpenCluely").font(.largeTitle).bold()
            Text("A free, 100% local interview assistant. Live audio transcription, screen reading, and AI answers — all on your Mac. No accounts, no cloud, no keys.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .frame(maxWidth: 460)
            Text("You'll need Ollama running with a model pulled (e.g. qwen2.5-coder:7b).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Let's grant permissions").font(.title).bold()
            Text("OpenCluely needs these macOS permissions. After clicking Grant, you may need to toggle it on in System Settings, then return here.")
                .font(.callout).foregroundStyle(.secondary)

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
                Text("Screen Recording is required to continue. After enabling it in System Settings, you may need to quit and relaunch the app.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func permissionCard(title: String, subtitle: String, granted: Bool, grant: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Grant", action: grant) }
        }
        .padding(14)
        .background(.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var tourStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How it works").font(.title).bold()
            tourRow("waveform", "Listen", "Capture meeting audio → live transcript → press ⌘↩ (or Send) for an answer.")
            tourRow("text.viewfinder", "Read Screen", "Answer a coding question that's visible on your screen.")
            tourRow("camera.viewfinder", "Screenshot", "Drag-select a region → solved by a vision model.")
            tourRow("paperclip", "Upload", "Add an image, PDF, or text file as context.")
            tourRow("eye", "Invisible", "Toggle to hide the overlay from screen-share (default: visible).")
            tourRow("slider.horizontal.3", "Settings", "Pick your model, choose a coding Mode, add your resume in Materials.")
        }
    }

    private func tourRow(_ icon: String, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout).bold()
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(.green)
            Text("You're all set").font(.largeTitle).bold()
            Text("The overlay bar is on your screen and in the menu bar (OC). Add your resume in Settings ▸ Materials for behavioral questions. Good luck!")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .frame(maxWidth: 460)
        }
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
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Welcome to OpenCluely"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: root)
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}
