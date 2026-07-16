//
//  AppCore.swift
//  cluelyopen
//
//  App delegate: owns the menu-bar item and the floating overlay panel,
//  and wires the overlay to OpenCluelyCore's AnswerEngine.
//

import AppKit
import SwiftUI
import OpenCluelyCore

final class AppCore: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var overlay: OverlayBarWindow?
    private let model = AnswerModel()

    // Core engine wiring (all local, no network except Ollama on localhost).
    private lazy var settings = Settings(store: UserDefaults.standard, tier: RAMTier.detected())
    private lazy var modes = ModesManager(store: UserDefaults.standard)
    private lazy var engine = AnswerEngine(client: OllamaClient(), modes: modes, settings: settings)

    // Listen (audio → transcript) wiring.
    private let transcript = TranscriptBuffer(maxChars: 4000)
    private let audio = AudioCapture()
    private var transcriber: Transcriber?   // lazily created on first Listen
    private var isListening = false

    /// Build the whisper transcriber from the bundled model, or fall back to the
    /// stub if the model resource is missing (keeps the app usable either way).
    private func makeTranscriber() -> Transcriber {
        if let transcriber { return transcriber }
        let model = settings.whisperModel   // e.g. "base.en"
        if let url = Bundle.main.url(forResource: "ggml-\(model)", withExtension: "bin") {
            transcriber = WhisperTranscriber(modelURL: url)
        } else {
            model_missing_warning()
            transcriber = StubTranscriber()
        }
        return transcriber!
    }

    private func model_missing_warning() {
        model.status = "Whisper model ggml-\(settings.whisperModel).bin not found in app bundle."
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar app, no dock icon
        setupStatusItem()
        showOverlay()
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "OC"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Overlay", action: #selector(toggleOverlay), keyEquivalent: "\\"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit OpenCluely",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    // MARK: - Overlay

    private func showOverlay() {
        let view = OverlayBarView(
            model: model,
            onSubmit: { [weak self] q in self?.askUsingCurrentContext(q) },
            onScreenshot: { [weak self] in self?.model.status = "Screenshot: coming soon" },
            onReadScreen: { [weak self] in self?.model.status = "Read screen: coming soon" },
            onToggleListen: { [weak self] in self?.toggleListen() }
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 560, height: 120)
        let panel = OverlayBarWindow(content: host)
        panel.setFrameOrigin(settings.overlayOrigin)
        panel.orderFrontRegardless()
        overlay = panel
    }

    @objc private func toggleOverlay() {
        guard let overlay else { return }
        if overlay.isVisible {
            overlay.orderOut(nil)
        } else {
            overlay.orderFrontRegardless()
        }
    }

    // MARK: - Listen (audio → transcript)

    private func toggleListen() {
        if isListening {
            audio.stop()
            isListening = false
            model.listening = false
            model.status = "Stopped listening."
            return
        }
        let transcriber = makeTranscriber()
        Task { @MainActor in
            do {
                try await audio.start { [weak self] pcm in
                    guard let self else { return }
                    Task {
                        let text = await transcriber.transcribe(pcm)
                        if !text.isEmpty {
                            self.transcript.append(text + " ")
                            await MainActor.run {
                                self.model.status = "Heard: …\(String(self.transcript.recent.suffix(60)))"
                            }
                        }
                    }
                }
                isListening = true
                model.listening = true
                model.status = "Listening… (speak or play audio, then press ⌘↩ to answer)"
            } catch {
                model.status = "Audio capture needs Screen Recording permission (System Settings ▸ Privacy & Security ▸ Screen Recording). \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Ask

    /// When listening, use the recent transcript as context; otherwise ask plainly.
    private func askUsingCurrentContext(_ q: String) {
        let context: AnswerContext = isListening && !transcript.recent.isEmpty
            ? .text(transcript.recent)
            : .none
        ask(q, context: context)
    }

    private func ask(_ q: String, context: AnswerContext) {
        model.query = q
        model.answer = ""
        model.status = ""
        Task { @MainActor in
            do {
                for try await tok in engine.answer(userText: q, context: context) {
                    model.answer += tok
                }
            } catch LLMError.notRunning {
                model.status = "Ollama isn't running. Start it in Terminal: ollama serve"
            } catch LLMError.modelMissing(let m) {
                model.status = "Model missing. In Terminal: ollama pull \(m)"
            } catch LLMError.http(let code) {
                model.status = "Ollama error (HTTP \(code))."
            } catch {
                model.status = "Error: \(error.localizedDescription)"
            }
        }
    }
}
