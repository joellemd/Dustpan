import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched with `swift run`, where there is no app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    // The menu bar item keeps the app alive after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct DustpanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Dustpan", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 920, minHeight: 600)
                .tint(Theme.accent)
        }
        .defaultSize(width: 1120, height: 720)

        MenuBarExtra("Dustpan", systemImage: "sparkles") {
            MenuBarView()
                .environment(model)
                .tint(Theme.accent)
        }
        .menuBarExtraStyle(.window)
    }
}

enum Theme {
    static let accent = Color(red: 0.14, green: 0.34, blue: 0.84)
    static let review = Color(red: 0.72, green: 0.38, blue: 0.05)
}
