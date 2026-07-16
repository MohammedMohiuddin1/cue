//
//  ContentView.swift
//  cluelyopen
//
//  The compact command-bar overlay view + its observable model.
//

import SwiftUI
import Combine

/// One completed Q&A exchange, kept for the History view.
struct Exchange: Identifiable {
    let id = UUID()
    let query: String
    let answer: String
    let contextLabel: String
}

/// Holds the live query, streamed answer, and a status line for the overlay.
final class AnswerModel: ObservableObject {
    @Published var query: String = ""
    @Published var answer: String = ""
    @Published var status: String = ""
    @Published var contextLabel: String = ""   // e.g. "Viewed screen", "From meeting audio"
    @Published var listening: Bool = false
    @Published var invisible: Bool = false      // hidden from screen-share when true
    @Published var availableModels: [String] = []
    @Published var currentModel: String = ""

    // Conversation-flow UI state.
    @Published var collapsed: Bool = false      // conversation box hidden when true
    @Published var showHistory: Bool = false
    @Published var history: [Exchange] = []

    /// True when there's something to show in the conversation box.
    var hasConversation: Bool {
        !query.isEmpty || !answer.isEmpty || !status.isEmpty
    }

    /// Placeholder text that reflects the current state (like Cluely).
    var placeholder: String {
        if listening { return "Ask about the conversation, or ⌘↩ for Answer" }
        if !answer.isEmpty { return "Ask follow-up" }
        return "Ask anything, or ⌘↩ for Answer"
    }
}

/// The translucent command bar: an input row plus a toolbar row of feature icons.
struct OverlayBarView: View {
    @ObservedObject var model: AnswerModel
    @State private var input: String = ""

    var onSubmit: (String) -> Void
    var onToggleListen: () -> Void
    var onToggleInvisible: () -> Void
    var onReadScreen: () -> Void
    var onSelectModel: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Collapsible conversation / history box.
            if model.showHistory {
                historyBox
            } else if model.hasConversation && !model.collapsed {
                conversationBox
            }

            inputRow
            toolbarRow
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .frame(width: 620)
    }

    // MARK: - Conversation box

    private var conversationBox: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if !model.query.isEmpty {
                    Text(model.query)
                        .font(.callout)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.blue.opacity(0.85), in: Capsule())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if !model.contextLabel.isEmpty {
                    Text(model.contextLabel)
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !model.answer.isEmpty {
                    Text(model.answer)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Copy button under the answer (like Cluely).
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.answer, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy answer")
                }
                if !model.status.isEmpty {
                    Text(model.status)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 2)
        }
        .frame(maxHeight: 300)
    }

    private var historyBox: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("History").font(.headline)
                    Spacer()
                    Button("Done") { model.showHistory = false }.buttonStyle(.plain).font(.caption)
                }
                if model.history.isEmpty {
                    Text("No past answers yet.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.history.reversed()) { ex in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ex.query).font(.callout).foregroundStyle(.blue)
                        Text(ex.answer).font(.caption).foregroundStyle(.primary).lineLimit(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                }
            }
        }
        .frame(maxHeight: 320)
    }

    // MARK: - Input row

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField(model.placeholder, text: $input)
                .textFieldStyle(.plain)
                .font(.body)
                .onSubmit(submit)
            Button(action: submit) {
                Image(systemName: "return")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(6)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Toolbar row (icon-only, Cluely-style)

    private var toolbarRow: some View {
        HStack(spacing: 18) {
            iconButton("waveform", active: model.listening, activeColor: .blue,
                       help: "Listen to the meeting audio", action: onToggleListen)
            iconButton("eye", active: false, activeColor: .primary,
                       help: "Read the question on your screen", action: onReadScreen)
            iconButton(model.invisible ? "eye.slash.fill" : "shield",
                       active: model.invisible, activeColor: .green,
                       help: model.invisible ? "Invisible to screen-share" : "Visible — click to hide",
                       action: onToggleInvisible)

            Divider().frame(height: 16)

            iconButton("clock.arrow.circlepath", active: model.showHistory, activeColor: .primary,
                       help: "History", action: { model.showHistory.toggle() })
            iconButton(model.collapsed ? "chevron.up" : "chevron.down", active: false, activeColor: .primary,
                       help: model.collapsed ? "Expand" : "Collapse",
                       action: { model.collapsed.toggle() })

            Spacer()

            // Model picker.
            Menu {
                if model.availableModels.isEmpty {
                    Text("No models — run: ollama pull llama3.2")
                }
                ForEach(model.availableModels, id: \.self) { name in
                    Button(name) { onSelectModel(name) }
                }
            } label: {
                Label(model.currentModel.isEmpty ? "Model" : model.currentModel, systemImage: "cpu")
                    .labelStyle(.titleAndIcon).font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Choose which local model answers")
        }
    }

    private func iconButton(_ symbol: String, active: Bool, activeColor: Color,
                            help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(active ? activeColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func submit() {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        input = ""
        onSubmit(q)
    }
}
