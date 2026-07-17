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
    @State private var materials: String

    init(settings: OpenCluelyCore.Settings, modes: ModesManager, installedModels: [String]) {
        self.settings = settings
        self.modes = modes
        self.installedModels = installedModels
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
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 580, height: 460)
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
