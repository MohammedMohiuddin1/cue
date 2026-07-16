//
//  cluelyopenApp.swift
//  cluelyopen
//
//  OpenCluely — invisible interview assistant (menu-bar app).
//

import SwiftUI

@main
struct cluelyopenApp: App {
    // AppCore owns the menu-bar item and the floating overlay window.
    @NSApplicationDelegateAdaptor(AppCore.self) private var appCore

    var body: some Scene {
        // No normal window — the UI lives in the floating overlay panel that
        // AppCore creates. An empty Settings scene keeps SwiftUI's App happy.
        Settings {
            EmptyView()
        }
    }
}
