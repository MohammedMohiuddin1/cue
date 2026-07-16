//
//  ScreenshotCapture.swift
//  cluelyopen
//
//  Interactive region screenshot using macOS's built-in `screencapture -i`
//  (the standard crosshair drag-select). Returns PNG bytes for the vision model.
//

import Foundation

enum ScreenshotCapture {
    /// Let the user drag-select a screen region; returns PNG data, or nil if
    /// they pressed Esc / selected nothing.
    static func captureRegion() async -> Data? {
        let tmp = NSTemporaryDirectory() + "opencluely-\(UUID().uuidString).png"
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                // -i interactive region select, -x no capture sound.
                proc.arguments = ["-i", "-x", tmp]
                do {
                    try proc.run()
                    proc.waitUntilExit()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                defer { try? FileManager.default.removeItem(atPath: tmp) }
                guard FileManager.default.fileExists(atPath: tmp),
                      let data = try? Data(contentsOf: URL(fileURLWithPath: tmp)),
                      !data.isEmpty else {
                    continuation.resume(returning: nil)   // user canceled
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }
}
