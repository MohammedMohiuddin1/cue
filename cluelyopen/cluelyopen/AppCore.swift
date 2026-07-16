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
            onSubmit: { [weak self] q in self?.ask(q, context: .none) },
            onScreenshot: { [weak self] in self?.model.status = "Screenshot: coming soon" },
            onReadScreen: { [weak self] in self?.model.status = "Read screen: coming soon" },
            onToggleListen: { [weak self] in self?.toggleListenPlaceholder() }
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

    private func toggleListenPlaceholder() {
        model.listening.toggle()
        model.status = model.listening ? "Listening: coming soon" : ""
    }

    // MARK: - Ask

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
