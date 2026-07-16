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
    @State private var hoverTip: String = ""   // custom tooltip (reliable on overlay panel)

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
            // Listen — waveform, blue + filled when active.
            iconButton(model.listening ? "waveform.circle.fill" : "waveform",
                       active: model.listening, activeColor: .blue,
                       tip: model.listening ? "Stop listening" : "Listen to meeting audio",
                       action: onToggleListen)

            // Read Screen — a text-viewfinder (distinct from the invisibility eye).
            iconButton("text.viewfinder", active: false, activeColor: .primary,
                       tip: "Read the question on your screen", action: onReadScreen)

            // Invisibility — open eye (visible) vs crossed eye + green (invisible).
            iconButton(model.invisible ? "eye.slash.fill" : "eye",
                       active: model.invisible, activeColor: .green,
                       tip: model.invisible ? "Invisible to screen-share — click to show"
                                            : "Visible — click to hide from screen-share",
                       action: onToggleInvisible)

            Divider().frame(height: 16)

            // History.
            iconButton("clock.arrow.circlepath", active: model.showHistory, activeColor: .accentColor,
                       tip: "History", action: { model.showHistory.toggle() })

            // Collapse / expand the conversation box.
            iconButton(model.collapsed ? "chevron.up" : "chevron.down", active: false, activeColor: .primary,
                       tip: model.collapsed ? "Expand conversation" : "Collapse conversation",
                       action: { model.collapsed.toggle() })

            Spacer()

            // Tooltip text (shows on hover — reliable on our overlay panel).
            if !hoverTip.isEmpty {
                Text(hoverTip)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .transition(.opacity)
            }

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
        }
    }

    private func iconButton(_ symbol: String, active: Bool, activeColor: Color,
                            tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(active ? activeColor : .secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tip)   // native tooltip (fallback)
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.12)) {
                hoverTip = inside ? tip : ""
            }
        }
    }

    private func submit() {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        input = ""
        onSubmit(q)
    }
}
