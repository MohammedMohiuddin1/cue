//
//  ContentView.swift
//  cluelyopen
//
//  The compact command-bar overlay view + its observable model.
//

import SwiftUI
import Combine

/// Holds the live query, streamed answer, and a status line for the overlay.
final class AnswerModel: ObservableObject {
    @Published var query: String = ""
    @Published var answer: String = ""
    @Published var status: String = ""
    @Published var listening: Bool = false
    @Published var invisible: Bool = false   // hidden from screen-share when true
    @Published var availableModels: [String] = []
    @Published var currentModel: String = ""
}

/// The translucent command bar: an input row plus a toolbar row of feature icons.
struct OverlayBarView: View {
    @ObservedObject var model: AnswerModel
    @State private var input: String = ""

    var onSubmit: (String) -> Void
    var onToggleListen: () -> Void
    var onToggleInvisible: () -> Void
    var onSelectModel: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.answer.isEmpty || !model.query.isEmpty || !model.status.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if !model.query.isEmpty {
                            Text(model.query)
                                .font(.callout)
                                .foregroundStyle(.blue)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        if !model.answer.isEmpty {
                            Text(model.answer)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                        if !model.status.isEmpty {
                            Text(model.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
            }

            HStack(spacing: 8) {
                TextField("Ask anything, or ⌘↩ for Answer", text: $input)
                    .textFieldStyle(.plain)
                    .onSubmit(submit)
                Button(action: submit) {
                    Image(systemName: "return")
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 16) {
                // Listen (meeting audio → answer). Working.
                Button(action: onToggleListen) {
                    Label(model.listening ? "Listening" : "Listen",
                          systemImage: model.listening ? "waveform.circle.fill" : "waveform")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(model.listening ? .blue : .primary)
                }
                .buttonStyle(.plain)
                .help("Listen to the meeting audio, then press ⌘↩ to answer")

                // Invisibility toggle. OFF = normal visible window;
                // ON = hidden from screen-share/recording.
                Button(action: onToggleInvisible) {
                    Label(model.invisible ? "Invisible" : "Visible",
                          systemImage: model.invisible ? "eye.slash.fill" : "eye")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(model.invisible ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help(model.invisible
                      ? "Invisible to screen-share (click to make visible)"
                      : "Visible to everyone (click to hide from screen-share)")

                Spacer()

                // Model picker — lists models actually pulled in Ollama.
                Menu {
                    if model.availableModels.isEmpty {
                        Text("No models found — run: ollama pull llama3.2")
                    }
                    ForEach(model.availableModels, id: \.self) { name in
                        Button(name) { onSelectModel(name) }
                    }
                } label: {
                    Label(model.currentModel.isEmpty ? "Model" : model.currentModel,
                          systemImage: "cpu")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Choose which local model answers")
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(width: 560)
    }

    private func submit() {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        input = ""
        onSubmit(q)
    }
}
