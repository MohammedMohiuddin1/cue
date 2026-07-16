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
}

/// The translucent command bar: an input row plus a toolbar row of feature icons.
struct OverlayBarView: View {
    @ObservedObject var model: AnswerModel
    @State private var input: String = ""

    var onSubmit: (String) -> Void
    var onScreenshot: () -> Void
    var onReadScreen: () -> Void
    var onToggleListen: () -> Void

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
                toolbarButton("photo", help: "Screenshot a region", action: onScreenshot)
                toolbarButton("eye", help: "Read the screen", action: onReadScreen)
                toolbarButton(model.listening ? "waveform.circle.fill" : "waveform",
                              help: "Listen to the meeting", action: onToggleListen)
                Spacer()
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(width: 560)
    }

    private func toolbarButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
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
