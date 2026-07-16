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
    // Use 127.0.0.1 (not "localhost") so macOS doesn't resolve to IPv6 ::1,
    // where Ollama isn't listening (connection refused).
    private lazy var engine = AnswerEngine(
        client: OllamaClient(baseURL: URL(string: "http://127.0.0.1:11434")!),
        modes: modes,
        settings: settings
    )

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
            onToggleListen: { [weak self] in self?.toggleListen() },
            onToggleInvisible: { [weak self] in self?.toggleInvisible() },
            onSelectModel: { [weak self] name in self?.selectModel(name) }
        )
        let host = NSHostingView(rootView: view)
        // Let the hosting view drive the window size so the answer area can grow.
        host.sizingOptions = [.preferredContentSize]
        host.translatesAutoresizingMaskIntoConstraints = true
        let panel = OverlayBarWindow(content: host)
        panel.setContentSize(NSSize(width: 588, height: 120))
        panel.setFrameOrigin(settings.overlayOrigin)
        panel.orderFrontRegardless()
        overlay = panel

        model.currentModel = settings.textModel
        refreshModelList()
    }

    /// Load the models the user has actually pulled in Ollama, and if the
    /// currently-selected model isn't installed, auto-pick an installed one so
    /// the app works out of the box.
    private func refreshModelList() {
        Task { @MainActor in
            let installed = await ModelList.installed()
            model.availableModels = installed
            if !installed.contains(settings.textModel), let first = installed.first {
                settings.textModel = first
                model.currentModel = first
                model.status = "Using model: \(first)"
            }
        }
    }

    private func selectModel(_ name: String) {
        settings.textModel = name
        model.currentModel = name
        model.status = "Model set to \(name)"
    }

    @objc private func toggleOverlay() {
        guard let overlay else { return }
        if overlay.isVisible {
            overlay.orderOut(nil)
        } else {
            overlay.orderFrontRegardless()
        }
    }

    /// Toggle whether the overlay is hidden from screen-share / recording.
    private func toggleInvisible() {
        guard let overlay else { return }
        let nowInvisible = overlay.toggleCaptureExclusion()
        model.invisible = nowInvisible
        model.status = nowInvisible
            ? "Invisible mode ON — hidden from screen-share (not from ScreenCaptureKit recorders on macOS 15+)."
            : "Visible mode — everyone can see this window."
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
        model.status = "Thinking…"
        NSLog("OpenCluely ask: q=\"%@\" model=%@", q, settings.textModel)
        Task { @MainActor in
            var tokenCount = 0
            do {
                for try await tok in engine.answer(userText: q, context: context) {
                    tokenCount += 1
                    model.answer += tok
                    if model.status == "Thinking…" { model.status = "" }
                }
                NSLog("OpenCluely ask: done, %d tokens, answerLen=%d", tokenCount, model.answer.count)
                if tokenCount == 0 {
                    model.status = "No response from model (0 tokens). Check the model name in Ollama."
                }
            } catch LLMError.notRunning {
                NSLog("OpenCluely ask: LLMError.notRunning")
                model.status = "Ollama isn't running. Start it in Terminal: ollama serve"
            } catch LLMError.modelMissing(let m) {
                NSLog("OpenCluely ask: LLMError.modelMissing(%@)", m)
                model.status = "Model missing. In Terminal: ollama pull \(m)"
            } catch LLMError.http(let code) {
                NSLog("OpenCluely ask: LLMError.http(%d)", code)
                model.status = "Ollama error (HTTP \(code))."
            } catch {
                NSLog("OpenCluely ask: error %@", String(describing: error))
                model.status = "Error: \(error.localizedDescription)"
            }
        }
    }
}
