//
//  ContentView.swift
//  cluelyopen
//
//  The compact command-bar overlay view + its observable model.
//

import SwiftUI
import Combine

/// One entry in a session's continuous log — either a Q&A exchange or a chunk
/// of transcribed meeting audio.
struct SessionItem: Identifiable {
    enum Kind { case exchange(query: String, answer: String, contextLabel: String)
                case transcript(String) }
    let id = UUID()
    let kind: Kind
    let time = Date()
}

/// A finished (archived) session, browsable from History.
struct ArchivedSession: Identifiable {
    let id = UUID()
    let startedAt: Date
    let endedAt: Date
    let items: [SessionItem]

    var title: String {
        let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"
        return f.string(from: startedAt)
    }
}

/// Holds the live overlay state, the CURRENT session's log, and archived sessions.
final class AnswerModel: ObservableObject {
    // Live streaming state (the in-progress answer / transcript).
    @Published var query: String = ""
    @Published var answer: String = ""
    @Published var status: String = ""
    @Published var liveTranscript: String = ""
    @Published var contextLabel: String = ""

    // Session state.
    @Published var sessionActive: Bool = false
    @Published var sessionItems: [SessionItem] = []   // current session's log
    @Published var archived: [ArchivedSession] = []   // past sessions (History)
    private var sessionStart = Date()

    // Feature / UI state.
    @Published var listening: Bool = false
    @Published var invisible: Bool = false
    @Published var availableModels: [String] = []
    @Published var currentModel: String = ""
    @Published var collapsed: Bool = false
    @Published var showHistory: Bool = false

    /// True when there's anything to show in the current session's box.
    var hasConversation: Bool {
        sessionActive && (!sessionItems.isEmpty || !answer.isEmpty
                          || !liveTranscript.isEmpty || !status.isEmpty)
    }

    var placeholder: String {
        if listening { return "Ask about the conversation, or ⌘↩ for Answer" }
        if !sessionItems.isEmpty { return "Ask follow-up" }
        return "Ask anything, or ⌘↩ for Answer"
    }

    // MARK: - Session lifecycle

    /// Called at the first action; a no-op if a session is already running.
    func startSessionIfNeeded() {
        guard !sessionActive else { return }
        sessionActive = true
        sessionStart = Date()
        sessionItems = []
        collapsed = false
        showHistory = false
    }

    /// Append a completed Q&A to the current session log.
    func addExchange(query: String, answer: String, contextLabel: String) {
        startSessionIfNeeded()
        sessionItems.append(SessionItem(kind: .exchange(query: query, answer: answer,
                                                        contextLabel: contextLabel)))
    }

    /// Append a chunk of transcribed audio to the current session log.
    func addTranscript(_ text: String) {
        startSessionIfNeeded()
        sessionItems.append(SessionItem(kind: .transcript(text)))
    }

    /// End the session: archive it, clear the live state, ready for a fresh one.
    func endSession() {
        if sessionActive && !sessionItems.isEmpty {
            archived.append(ArchivedSession(startedAt: sessionStart, endedAt: Date(),
                                            items: sessionItems))
        }
        sessionActive = false
        sessionItems = []
        query = ""; answer = ""; status = ""; liveTranscript = ""; contextLabel = ""
        listening = false
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
    var onScreenshot: () -> Void
    var onSelectModel: (String) -> Void
    var onEndSession: () -> Void
    var onOpenSettings: () -> Void
    @State private var openedSession: ArchivedSession?

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

    // MARK: - Conversation box (continuous session log)

    private var conversationBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Session header with an End Session button.
            HStack {
                Circle().fill(.green).frame(width: 7, height: 7)
                Text("Session").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: onEndSession) {
                    Label("End", systemImage: "stop.circle")
                        .labelStyle(.titleAndIcon).font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("End this session (archived to History)")
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        // Everything that already happened this session.
                        ForEach(model.sessionItems) { item in
                            sessionItemView(item)
                        }
                        // The in-progress answer (streaming), not yet committed.
                        if !model.answer.isEmpty {
                            answerView(model.answer, contextLabel: model.contextLabel,
                                       query: model.query)
                        }
                        // The live transcript while listening.
                        if model.listening && !model.liveTranscript.isEmpty {
                            transcriptView(model.liveTranscript, live: true)
                        }
                        if !model.status.isEmpty {
                            Text(model.status).font(.caption).foregroundStyle(.secondary)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 260)
                // Throttle auto-scroll: only when the number of items changes or
                // the streaming text grows by a chunk — not on every token (which
                // triggers "update multiple times per frame").
                .onChange(of: model.sessionItems.count) {
                    withAnimation(.none) { proxy.scrollTo("bottom") }
                }
                .onChange(of: model.answer.count / 40) {
                    withAnimation(.none) { proxy.scrollTo("bottom") }
                }
                .onChange(of: model.liveTranscript.count / 40) {
                    withAnimation(.none) { proxy.scrollTo("bottom") }
                }
            }
        }
    }

    @ViewBuilder
    private func sessionItemView(_ item: SessionItem) -> some View {
        switch item.kind {
        case .exchange(let q, let a, let ctx):
            answerView(a, contextLabel: ctx, query: q)
        case .transcript(let t):
            transcriptView(t, live: false)
        }
    }

    private func transcriptView(_ text: String, live: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "waveform").font(.caption).foregroundStyle(.blue)
                Text(live ? "Live transcript" : "Transcript").font(.caption).foregroundStyle(.secondary)
            }
            Text(text).font(.callout).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func answerView(_ answer: String, contextLabel: String, query: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if !query.isEmpty {
                Text(query)
                    .font(.callout)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.blue.opacity(0.85), in: Capsule())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if !contextLabel.isEmpty {
                Text(contextLabel).font(.caption).foregroundStyle(.secondary)
            }
            Text(answer).font(.callout).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(answer, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc").font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).help("Copy answer")
        }
    }

    // MARK: - History (archived sessions)

    private var historyBox: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if let opened = openedSession {
                        Button { openedSession = nil } label: {
                            Label("Sessions", systemImage: "chevron.left").font(.caption)
                        }.buttonStyle(.plain)
                        Spacer()
                        Text(opened.title).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("History").font(.headline)
                        Spacer()
                        Button("Done") { model.showHistory = false }.buttonStyle(.plain).font(.caption)
                    }
                }

                if let opened = openedSession {
                    ForEach(opened.items) { item in sessionItemView(item) }
                } else if model.archived.isEmpty {
                    Text("No past sessions yet.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(model.archived.reversed()) { session in
                        Button { openedSession = session } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title).font(.callout)
                                    Text("\(session.items.count) items")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
        .frame(height: 300)
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
            // Screenshot a region → vision model.
            iconButton("camera.viewfinder", active: false, activeColor: .primary,
                       tip: "Screenshot a region and solve it", action: onScreenshot)

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

            // Settings.
            iconButton("slider.horizontal.3", active: false, activeColor: .primary,
                       tip: "Settings — models & modes", action: onOpenSettings)

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
