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

    // Read Screen (OCR) wiring.
    private let screenReader = ScreenReader()

    // Settings window.
    private let settingsWindow = SettingsWindowController()

    // Onboarding.
    private let permissions = PermissionsManager()
    private let onboarding = OnboardingWindowController()

    // Global hotkeys.
    private var hotkeys: HotkeyManager?

    /// Build the whisper transcriber from the bundled model, or fall back to the
    /// stub if the model resource is missing (keeps the app usable either way).
    /// Transcribed phrases arrive via the onText callback (worker-driven).
    private func makeTranscriber() -> Transcriber {
        if let transcriber { return transcriber }
        let name = settings.whisperModel   // e.g. "small.en"
        if let url = Bundle.main.url(forResource: "ggml-\(name)", withExtension: "bin") {
            transcriber = WhisperTranscriber(modelURL: url) { [weak self] phrase in
                guard let self else { return }
                let clean = Self.cleanSpeech(phrase)
                guard !clean.isEmpty else { return }
                self.transcript.append(clean + " ")
                // Live transcript grows in the current session box.
                self.model.startSessionIfNeeded()
                self.model.liveTranscript = self.transcript.recent
                self.model.status = ""
            }
        } else {
            model_missing_warning()
            transcriber = StubTranscriber()
        }
        return transcriber!
    }

    private func model_missing_warning() {
        model.status = "Whisper model ggml-\(settings.whisperModel).bin not found in app bundle."
    }

    /// Strip whisper's non-speech annotations like [MUSIC], (grunting),
    /// [BLANK_AUDIO], *screams* — keep only actual spoken words.
    private static func cleanSpeech(_ text: String) -> String {
        var s = text
        for pattern in ["\\[[^\\]]*\\]", "\\([^\\)]*\\)", "\\*[^\\*]*\\*"] {
            s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        // Collapse whitespace and drop stray leading punctuation from removed tags.
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: CharacterSet(charactersIn: " -–—>."))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar app, no dock icon
        setupStatusItem()
        showOverlay()
        startHotkeys()
        // First-run onboarding (permissions + tour).
        if onboarding.shouldShow {
            onboarding.show(permissions: permissions) { [weak self] in
                self?.overlay?.orderFrontRegardless()
            }
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "OC"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Overlay", action: #selector(toggleOverlay), keyEquivalent: "\\"))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Setup Guide…", action: #selector(showOnboarding), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit OpenCluely",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() {
        Task { @MainActor in
            let installed = await ModelList.installed()
            settingsWindow.show(settings: settings, modes: modes, installedModels: installed)
        }
    }

    @objc private func showOnboarding() {
        onboarding.show(permissions: permissions) { [weak self] in
            self?.overlay?.orderFrontRegardless()
        }
    }

    // MARK: - Overlay

    private func showOverlay() {
        let view = OverlayBarView(
            model: model,
            onSubmit: { [weak self] q in self?.askUsingCurrentContext(q) },
            onToggleListen: { [weak self] in self?.toggleListen() },
            onToggleInvisible: { [weak self] in self?.toggleInvisible() },
            onReadScreen: { [weak self] in self?.readScreen() },
            onScreenshot: { [weak self] in self?.captureScreenshot() },
            onUploadFile: { [weak self] in self?.uploadFile() },
            onSelectModel: { [weak self] name in self?.selectModel(name) },
            onEndSession: { [weak self] in self?.endSession() },
            onOpenSettings: { [weak self] in self?.openSettings() }
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

    // MARK: - Global hotkeys

    private func startHotkeys() {
        let h = HotkeyManager(handlers: .init(
            toggleOverlay: { [weak self] in self?.toggleOverlay() },
            answer: { [weak self] in self?.answerFromHotkey() },
            move: { [weak self] dx, dy in self?.moveOverlay(dx: dx, dy: dy) }
        ))
        h.start()
        hotkeys = h
    }

    /// ⌘↩ from anywhere: answer using the current context (transcript if
    /// listening, else the last query, else a generic prompt).
    private func answerFromHotkey() {
        if isListening && !transcript.recent.isEmpty {
            ask("Answer the most recent question from the conversation.",
                context: .text(transcript.recent))
        } else if !model.query.isEmpty {
            ask(model.query, context: .none)
        }
    }

    private func moveOverlay(dx: CGFloat, dy: CGFloat) {
        guard let overlay else { return }
        var origin = overlay.frame.origin
        origin.x += dx
        origin.y += dy
        overlay.setFrameOrigin(origin)
        settings.overlayOrigin = origin
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

    // MARK: - Session

    private func endSession() {
        // Stop listening if active, then archive + clear via the model.
        if isListening { audio.stop(); isListening = false }
        transcript.clear()
        model.endSession()
    }

    // MARK: - Listen (audio → transcript)

    private func toggleListen() {
        if isListening {
            audio.stop()
            isListening = false
            model.listening = false
            // Commit the captured transcript as a session item, then clear the live line.
            let captured = transcript.recent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !captured.isEmpty { model.addTranscript(captured) }
            transcript.clear()
            model.liveTranscript = ""
            model.status = "Stopped listening."
            return
        }
        model.startSessionIfNeeded()
        // Build the transcriber (starts its worker loop). Feed it raw audio;
        // transcribed phrases arrive via the onText callback set in makeTranscriber().
        let transcriber = makeTranscriber()
        transcript.clear()
        model.liveTranscript = ""
        model.collapsed = false
        model.showHistory = false
        Task { @MainActor in
            do {
                try await audio.start { pcm in
                    Task { _ = await transcriber.transcribe(pcm) }
                }
                isListening = true
                model.listening = true
                model.status = "Listening… (speak or play audio, then press ⌘↩ to answer)"
            } catch {
                model.status = "Audio capture needs Screen Recording permission (System Settings ▸ Privacy & Security ▸ Screen Recording). \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Read Screen (OCR)

    private func readScreen() {
        model.query = "Answer the question on my screen."
        model.answer = ""
        model.status = "Reading screen…"
        Task { @MainActor in
            do {
                let text = try await screenReader.readScreen()
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    model.status = "Nothing readable found on screen."
                    return
                }
                ask("Answer or solve the question shown on the screen.", context: .text(trimmed))
            } catch {
                model.status = "Read screen failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Region Screenshot (→ vision model)

    private func captureScreenshot() {
        Task { @MainActor in
            // Ensure a vision-capable model is available; pick one if the default
            // isn't installed, else guide the user to pull one.
            let installed = await ModelList.installed()
            // Show the crosshair FIRST so capture always feels responsive.
            model.status = "Select a region…"
            guard let png = await ScreenshotCapture.captureRegion() else {
                model.status = "Screenshot canceled."
                return
            }
            // Then ensure a vision model exists (auto-pick installed one, else guide).
            let vision = installed.first { name in
                ["llava", "vl", "vision", "moondream", "bakllava", "minicpm"].contains {
                    name.lowercased().contains($0)
                }
            }
            if !installed.contains(settings.visionModel) {
                if let vision { settings.visionModel = vision }
                else {
                    model.startSessionIfNeeded()
                    model.status = "Captured — but no vision model. In Terminal: ollama pull llava"
                    return
                }
            }
            ask("Solve or answer the problem shown in this image.", context: .image(png))
        }
    }

    // MARK: - File upload (→ context)

    private func uploadFile() {
        guard let file = FileImport.pickFile() else { return }
        model.startSessionIfNeeded()
        switch file {
        case .image(let data, let name):
            // Ensure a vision model, like the screenshot path.
            Task { @MainActor in
                let installed = await ModelList.installed()
                let vision = installed.first { n in
                    ["llava", "vl", "vision", "moondream", "bakllava", "minicpm"].contains {
                        n.lowercased().contains($0)
                    }
                }
                if let vision, !installed.contains(settings.visionModel) { settings.visionModel = vision }
                guard installed.contains(settings.visionModel) || vision != nil else {
                    model.status = "No vision model for images. In Terminal: ollama pull llava"
                    return
                }
                ask("Answer or solve the problem in this image.", context: .image(data),
                    label: "File: \(name)")
            }
        case .text(let text, let name):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                model.status = "No readable text in \(name)."
                return
            }
            // Cap very large files so we don't overflow the prompt.
            let capped = String(trimmed.prefix(8000))
            ask("Use this file as context and answer the current question or summarize it.",
                context: .text(capped), label: "File: \(name)")
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

    private func ask(_ q: String, context: AnswerContext, label: String? = nil) {
        model.startSessionIfNeeded()
        model.query = q
        model.answer = ""
        model.status = "Thinking…"
        model.collapsed = false
        model.showHistory = false
        // Explicit label wins (e.g. "File: resume.pdf"); otherwise infer from source.
        if let label {
            model.contextLabel = label
        } else {
            switch context {
            case .text where isListening: model.contextLabel = "From meeting audio"
            case .text: model.contextLabel = "Viewed screen"
            case .image: model.contextLabel = "From screenshot"
            case .none: model.contextLabel = ""
            }
        }
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
                } else {
                    // Commit the completed exchange to the current session log,
                    // then clear the live streaming fields.
                    model.addExchange(query: q, answer: model.answer,
                                      contextLabel: model.contextLabel)
                    model.query = ""; model.answer = ""; model.contextLabel = ""
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
