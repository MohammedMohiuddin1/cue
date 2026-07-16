//
//  ModelList.swift
//  cluelyopen
//
//  Fetches the list of models the user has pulled in Ollama, so the overlay
//  can offer a picker instead of guessing a default that may not be installed.
//

import Foundation

enum ModelList {
    /// Query Ollama's /api/tags for installed model names. Returns [] on failure.
    static func installed(baseURL: URL = URL(string: "http://127.0.0.1:11434")!) async -> [String] {
        let url = baseURL.appendingPathComponent("/api/tags")
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = obj["models"] as? [[String: Any]] else { return [] }
            return models.compactMap { $0["name"] as? String }.sorted()
        } catch {
            return []
        }
    }
}
