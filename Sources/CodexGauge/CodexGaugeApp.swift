import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        // Login launches happen before the desktop has completely settled. Presenting
        // once more avoids a running-but-invisible widget after signing in.
        for delay in [0.5, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSApplication.shared.windows
                    .filter { !$0.isMiniaturized }
                    .forEach { $0.orderFrontRegardless() }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct CodexGaugeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UsageStore()

    var body: some Scene {
        WindowGroup("Codex 额度", id: "widget") {
            WidgetView(store: store)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 164, height: 164)

        MenuBarExtra {
            MenuBarContent(store: store)
        } label: {
            Label(store.language.widgetTitle, systemImage: "gauge.with.dots.needle.67percent")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarContent: View {
    @ObservedObject var store: UsageStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(summary)
        Divider()
        Button(store.language.showWidget) {
            openWindow(id: "widget")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Button(store.language.refreshNow) { Task { await store.refresh() } }
        Button(store.alwaysOnTop ? store.language.stopKeepingOnTop : store.language.keepOnTop) {
            store.alwaysOnTop.toggle()
        }
        Toggle(
            store.launchAtLoginNeedsApproval
                ? store.language.launchAtLoginApproval
                : store.language.launchAtLogin,
            isOn: Binding(
                get: { store.launchAtLoginRequested },
                set: { store.setLaunchAtLogin($0) }
            )
        )
        if let error = store.launchAtLoginError {
            Text(error)
        }
        Picker(store.language.languageMenu, selection: $store.language) {
            Text("中文").tag(AppLanguage.chinese)
            Text("English").tag(AppLanguage.english)
        }
        Divider()
        Button(store.language.openCodex) { store.openCodex() }
        Button(store.language.quit) { NSApplication.shared.terminate(nil) }
    }

    private var summary: String {
        let five = store.snapshot.fiveHour.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—"
        let week = store.snapshot.weekly.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—"
        return "5H \(five) · \(store.language.weekSummaryLabel) \(week)"
    }
}
