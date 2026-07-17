//
//  SettingsWindow.swift
//  cluelyopen
//
//  Tabbed settings: General (models), Modes (coding personas), About.
//

import AppKit
import SwiftUI
import Combine
import OpenCluelyCore

struct SettingsRoot: View {
    let settings: OpenCluelyCore.Settings
    let modes: ModesManager
    let installedModels: [String]
    let permissions: PermissionsManager

    @State private var textModel: String
    @State private var visionModel: String
    @State private var whisperModel: String
    @State private var activeModeID: String
    @State private var materials: String

    @State private var hasScreen = false
    @State private var hasAccess = false
    private let ticker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    init(settings: OpenCluelyCore.Settings, modes: ModesManager, installedModels: [String], permissions: PermissionsManager) {
        self.settings = settings
        self.modes = modes
        self.installedModels = installedModels
        self.permissions = permissions
        _textModel = State(initialValue: settings.textModel)
        _visionModel = State(initialValue: settings.visionModel)
        _whisperModel = State(initialValue: settings.whisperModel)
        _activeModeID = State(initialValue: modes.activeMode.id)
        _materials = State(initialValue: settings.referenceMaterials)
    }

    private let whisperOptions = ["base.en", "small.en", "medium.en"]

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            modesTab.tabItem { Label("Modes", systemImage: "person.crop.rectangle.stack") }
            materialsTab.tabItem { Label("Materials", systemImage: "doc.text") }
            permissionsTab.tabItem { Label("Permissions", systemImage: "lock.shield") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 580, height: 460)
        .padding()
        .onReceive(ticker) { _ in
            hasScreen = permissions.hasScreenRecording
            hasAccess = permissions.hasAccessibility
        }
        .onAppear {
            hasScreen = permissions.hasScreenRecording
            hasAccess = permissions.hasAccessibility
        }
    }

    // MARK: General

    private var generalTab: some View {
        Form {
            Section("Text model (answers)") {
                modelPicker(selection: $textModel) { settings.textModel = $0 }
            }
            Section("Vision model (screenshots)") {
                modelPicker(selection: $visionModel) { settings.visionModel = $0 }
            }
            Section("Speech-to-text (Listen)") {
                Picker("Whisper model", selection: $whisperModel) {
                    ForEach(whisperOptions, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: whisperModel) { settings.whisperModel = $1 }
                Text("Larger = more accurate but slower. Restart Listen to apply.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// A picker over installed Ollama models, with the current value pinned in
    /// even if it isn't currently installed.
    private func modelPicker(selection: Binding<String>, onSet: @escaping (String) -> Void) -> some View {
        var options = installedModels
        if !options.contains(selection.wrappedValue) { options.insert(selection.wrappedValue, at: 0) }
        return Picker("Model", selection: selection) {
            ForEach(options, id: \.self) { Text($0).tag($0) }
        }
        .onChange(of: selection.wrappedValue) { _, new in onSet(new) }
    }

    // MARK: Modes

    private var modesTab: some View {
        HStack(spacing: 0) {
            List(modes.builtInModes, selection: $activeModeID) { mode in
                HStack {
                    VStack(alignment: .leading) {
                        Text(mode.name).font(.callout).bold()
                    }
                    Spacer()
                    if mode.id == activeModeID {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                    }
                }
                .tag(mode.id)
                .contentShape(Rectangle())
                .onTapGesture { activeModeID = mode.id }
            }
            .frame(width: 200)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                let mode = modes.builtInModes.first { $0.id == activeModeID } ?? modes.builtInModes[0]
                Text(mode.name).font(.title3).bold()
                Text(mode.systemPrompt.isEmpty
                     ? "Baseline mode — no custom prompt."
                     : mode.systemPrompt)
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Set Active") {
                    modes.setActive(id: activeModeID)
                }
                .disabled(modes.activeMode.id == activeModeID)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: Materials (resume / reference docs, always in context)

    private var materialsTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reference Materials").font(.title3).bold()
            Text("Your resume, project notes, or any reference text. This is always given to the model as context, so it can answer resume/project/behavioral questions — not just DSA.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button {
                    if let file = FileImport.pickFile(), case .text(let t, let name) = file {
                        let header = "\n\n--- \(name) ---\n"
                        materials += (materials.isEmpty ? "" : header) + t
                        settings.referenceMaterials = materials
                    }
                } label: {
                    Label("Add file (PDF / text)", systemImage: "plus.circle")
                }
                Spacer()
                Button("Clear") {
                    materials = ""
                    settings.referenceMaterials = ""
                }.foregroundStyle(.red)
                Text("\(materials.count) chars").font(.caption).foregroundStyle(.secondary)
            }

            TextEditor(text: $materials)
                .font(.system(.callout, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3)))
                .onChange(of: materials) { settings.referenceMaterials = $1 }

            Text("Tip: keep it concise — very long materials use more tokens and slow answers.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(4)
    }

    // MARK: Permissions

    private var permissionsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permissions").font(.title3).bold()
            Text("OpenCluely uses these macOS permissions. Everything runs locally — these only gate OS capabilities.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            permissionRow(
                title: "Screen Recording",
                subtitle: "Captures meeting audio, reads your screen, and takes screenshots.",
                granted: hasScreen,
                open: { permissions.openScreenRecordingSettings() }
            )
            permissionRow(
                title: "Accessibility",
                subtitle: "Enables global keyboard shortcuts (⌘\\, ⌘↩, ⌘+arrows).",
                granted: hasAccess,
                open: { permissions.openAccessibilitySettings() }
            )

            Text("If you just enabled a permission, you may need to quit and relaunch OpenCluely for it to take effect.")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func permissionRow(title: String, subtitle: String, granted: Bool, open: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(granted ? "Granted" : "Not granted")
                    .font(.caption).foregroundStyle(granted ? .green : .orange)
                Button("Open Settings", action: open).font(.caption)
            }
        }
        .padding(14)
        .background(.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: About

    private var aboutTab: some View {
        VStack(spacing: 10) {
            Text("OpenCluely").font(.largeTitle).bold()
            Text("Free, open-source, 100% local interview assistant.")
                .foregroundStyle(.secondary)
            Text("All inference runs on your Mac via Ollama + whisper.cpp. No accounts, no cloud, no keys.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Divider().padding(.vertical, 6)
            Text("Invisibility hides the overlay from default screen-share, but not from ScreenCaptureKit recorders on macOS 15+.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

final class SettingsWindowController {
    private var window: NSWindow?

    func show(settings: OpenCluelyCore.Settings, modes: ModesManager, installedModels: [String], permissions: PermissionsManager) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = SettingsRoot(settings: settings, modes: modes, installedModels: installedModels, permissions: permissions)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "OpenCluely Settings"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: root)
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}
