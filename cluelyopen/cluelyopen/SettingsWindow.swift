//
//  SettingsWindow.swift
//  cluelyopen
//
//  Tabbed settings: General (models), Modes (coding personas), About.
//

import AppKit
import SwiftUI
import OpenCluelyCore

struct SettingsRoot: View {
    let settings: OpenCluelyCore.Settings
    let modes: ModesManager
    let installedModels: [String]

    @State private var textModel: String
    @State private var visionModel: String
    @State private var whisperModel: String
    @State private var activeModeID: String

    init(settings: OpenCluelyCore.Settings, modes: ModesManager, installedModels: [String]) {
        self.settings = settings
        self.modes = modes
        self.installedModels = installedModels
        _textModel = State(initialValue: settings.textModel)
        _visionModel = State(initialValue: settings.visionModel)
        _whisperModel = State(initialValue: settings.whisperModel)
        _activeModeID = State(initialValue: modes.activeMode.id)
    }

    private let whisperOptions = ["base.en", "small.en", "medium.en"]

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            modesTab.tabItem { Label("Modes", systemImage: "person.crop.rectangle.stack") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 440)
        .padding()
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

    func show(settings: OpenCluelyCore.Settings, modes: ModesManager, installedModels: [String]) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = SettingsRoot(settings: settings, modes: modes, installedModels: installedModels)
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
