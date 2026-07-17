//
//  FileImport.swift
//  cluelyopen
//
//  Import a file (image, PDF, or text) to use as context for an answer.
//  Images go to the vision model; PDFs/text are extracted to text context.
//

import AppKit
import PDFKit
import UniformTypeIdentifiers

enum ImportedFile {
    case image(Data, name: String)   // send to vision model
    case text(String, name: String)  // include as text context
}

enum FileImport {
    /// Show an open panel and return the imported file's content, or nil if
    /// canceled / unsupported.
    @MainActor
    static func pickFile() -> ImportedFile? {
        // Our overlay is a non-activating accessory app; the open panel needs the
        // app to be active and frontmost or it won't appear/take focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(.accessory) }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .pdf, .plainText, .sourceCode, .text, .data]
        panel.message = "Choose a file to use as context (image, PDF, or text)"
        panel.level = .modalPanel
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return load(url)
    }

    /// Load a file URL into an ImportedFile based on its type.
    static func load(_ url: URL) -> ImportedFile? {
        let name = url.lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension)

        // Image → vision.
        if let type, type.conforms(to: .image), let data = try? Data(contentsOf: url) {
            return .image(data, name: name)
        }
        // PDF → extract text.
        if url.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: url) {
            let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }
                .joined(separator: "\n")
            return .text(text, name: name)
        }
        // Anything else → try as UTF-8 text.
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return .text(text, name: name)
        }
        return nil
    }
}
