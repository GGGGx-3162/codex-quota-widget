import Foundation

struct LaunchAtLoginManager {
    static let label = "com.local.codexgauge.login"

    private let fileManager = FileManager.default

    private var launchAgentsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    private var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(Self.label).plist")
    }

    var isInstalled: Bool {
        fileManager.fileExists(atPath: plistURL.path)
    }

    func install() throws {
        try fileManager.createDirectory(
            at: launchAgentsDirectory,
            withIntermediateDirectories: true
        )

        let appPath = Bundle.main.bundleURL.path
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            throw LaunchAtLoginError.notRunningFromAppBundle
        }

        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": ["/usr/bin/open", appPath],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: .atomic)

        _ = try? runLaunchctl(["bootout", serviceTarget], allowFailure: true)
        try runLaunchctl(["bootstrap", domainTarget, plistURL.path])
        try runLaunchctl(["enable", serviceTarget])
    }

    func uninstall() throws {
        _ = try? runLaunchctl(["bootout", serviceTarget], allowFailure: true)
        if fileManager.fileExists(atPath: plistURL.path) {
            try fileManager.removeItem(at: plistURL)
        }
    }

    private var domainTarget: String {
        "gui/\(getuid())"
    }

    private var serviceTarget: String {
        "\(domainTarget)/\(Self.label)"
    }

    @discardableResult
    private func runLaunchctl(
        _ arguments: [String],
        allowFailure: Bool = false
    ) throws -> Int32 {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 || allowFailure else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw LaunchAtLoginError.launchctlFailed(detail ?? "未知错误")
        }
        return process.terminationStatus
    }
}

private enum LaunchAtLoginError: LocalizedError {
    case notRunningFromAppBundle
    case launchctlFailed(String)

    var errorDescription: String? {
        switch self {
        case .notRunningFromAppBundle:
            return "请先把应用放入“应用程序”文件夹后再开启"
        case let .launchctlFailed(detail):
            return "系统启动服务注册失败：\(detail)"
        }
    }
}
