import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class UsageStore: ObservableObject {
    @Published var snapshot = UsageSnapshot.empty
    @Published var isRefreshing = false
    @Published var hasLoaded = false
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginNeedsApproval = false
    @Published private(set) var launchAtLoginError: String?
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey) }
    }
    @Published var alwaysOnTop: Bool {
        didSet { UserDefaults.standard.set(alwaysOnTop, forKey: Self.alwaysOnTopKey) }
    }

    private let reader: CodexUsageReader
    private let launchAtLoginManager = LaunchAtLoginManager()
    private var autoRefreshTask: Task<Void, Never>?
    private static let alwaysOnTopKey = "CodexGauge.alwaysOnTop"
    private static let languageKey = "CodexGauge.language"

    var launchAtLoginRequested: Bool {
        launchAtLoginEnabled || launchAtLoginNeedsApproval
    }

    init(reader: CodexUsageReader = CodexUsageReader()) {
        self.reader = reader
        self.language = UserDefaults.standard.string(forKey: Self.languageKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .chinese
        self.alwaysOnTop = UserDefaults.standard.object(forKey: Self.alwaysOnTopKey) as? Bool ?? true
        refreshLaunchAtLoginStatus()
        repairLaunchAtLoginIfNeeded()
        autoRefreshTask = Task { [weak self] in
            await self?.runAutoRefresh()
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        snapshot = await reader.read()
        refreshLaunchAtLoginStatus()
        hasLoaded = true
        isRefreshing = false
    }

    private func runAutoRefresh() async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    func openCodex() {
        let candidates = [
            URL(fileURLWithPath: "/Applications/Codex.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Codex.app")
        ]
        if let appURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil

        do {
            if enabled {
                try launchAtLoginManager.install()
                try? SMAppService.mainApp.register()
            } else {
                try launchAtLoginManager.uninstall()
                try? SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLoginStatus()
        } catch {
            refreshLaunchAtLoginStatus()
            launchAtLoginError = "\(language.launchAtLoginFailure)：\(error.localizedDescription)"
            NSSound.beep()
        }
    }

    func refreshLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = launchAtLoginManager.isInstalled || status == .enabled
        launchAtLoginNeedsApproval = !launchAtLoginManager.isInstalled && status == .requiresApproval
    }

    private func repairLaunchAtLoginIfNeeded() {
        guard SMAppService.mainApp.status == .enabled,
              !launchAtLoginManager.isInstalled else { return }

        do {
            try launchAtLoginManager.install()
            refreshLaunchAtLoginStatus()
        } catch {
            launchAtLoginError = "\(language.launchAtLoginRepairFailure)：\(error.localizedDescription)"
        }
    }
}
