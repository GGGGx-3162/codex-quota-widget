import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese
    case english

    var id: Self { self }

    var widgetTitle: String { self == .chinese ? "Codex 额度" : "Codex Quota" }
    var fiveHourTitle: String { self == .chinese ? "5 小时额度" : "5-hour quota" }
    var weekLabel: String { self == .chinese ? "周" : "W" }
    var weeklyTitle: String { self == .chinese ? "每周额度" : "Weekly quota" }
    var showWidget: String { self == .chinese ? "显示小组件" : "Show Widget" }
    var refreshNow: String { self == .chinese ? "立即刷新" : "Refresh Now" }
    var keepOnTop: String { self == .chinese ? "保持在最前" : "Keep on Top" }
    var stopKeepingOnTop: String { self == .chinese ? "取消置顶" : "Stop Keeping on Top" }
    var launchAtLogin: String { self == .chinese ? "登录时自动启动" : "Launch at Login" }
    var launchAtLoginApproval: String {
        self == .chinese ? "登录时自动启动（需系统确认）" : "Launch at Login (Approval Required)"
    }
    var languageMenu: String { self == .chinese ? "语言" : "Language" }
    var openCodex: String { self == .chinese ? "打开 Codex" : "Open Codex" }
    var quit: String { self == .chinese ? "退出" : "Quit" }
    var noAvailableRecord: String { self == .chinese ? "暂无可用记录" : "No recent record" }
    var remaining: String { self == .chinese ? "剩余" : "remaining" }
    var resets: String { self == .chinese ? "重置" : "reset" }
    var weekSummaryLabel: String { self == .chinese ? "周" : "W" }
    var launchAtLoginFailure: String {
        self == .chinese ? "登录启动设置失败" : "Launch at Login failed"
    }
    var launchAtLoginRepairFailure: String {
        self == .chinese ? "登录启动自动修复失败" : "Launch at Login repair failed"
    }
}
