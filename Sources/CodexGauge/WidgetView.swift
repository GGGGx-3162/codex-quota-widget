import AppKit
import SwiftUI

struct WidgetView: View {
    @ObservedObject var store: UsageStore

    private let glassShape = RoundedRectangle(cornerRadius: 26, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            CompactQuotaRow(
                label: "5H",
                title: store.language.fiveHourTitle,
                symbol: "clock.fill",
                metric: store.snapshot.fiveHour,
                loading: !store.hasLoaded,
                language: store.language
            )

            CompactQuotaRow(
                label: store.language.weekLabel,
                title: store.language.weeklyTitle,
                symbol: "calendar",
                metric: store.snapshot.weekly,
                loading: !store.hasLoaded,
                language: store.language
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(width: 164, height: 164, alignment: .topLeading)
        .background {
            ZStack {
                FrostedGlassView()
                Color(red: 0.28, green: 0.50, blue: 0.34).opacity(0.52)
                LinearGradient(
                    colors: [.white.opacity(0.045), .clear, .black.opacity(0.025)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipShape(glassShape)
        .overlay {
            glassShape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(red: 0.72, green: 0.93, blue: 0.76).opacity(0.42),
                            Color(red: 0.55, green: 0.83, blue: 0.60).opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.15
                )
        }
        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
        .background(WindowConfigurator(alwaysOnTop: store.alwaysOnTop))
        .contextMenu { contextMenu }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(store.language.widgetTitle)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(store.language.widgetTitle)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.value)

            Spacer()

            Circle()
                .fill(store.hasLoaded ? Palette.progress : Palette.track)
                .frame(width: 5, height: 5)
                .opacity(store.isRefreshing ? 0.5 : 1)
                .animation(.easeInOut(duration: 0.4), value: store.isRefreshing)
        }
        .frame(height: 20)
    }

    @ViewBuilder
    private var contextMenu: some View {
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
}

private struct CompactQuotaRow: View {
    let label: String
    let title: String
    let symbol: String
    let metric: QuotaMetric?
    let loading: Bool
    let language: AppLanguage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedProgress = 0.0
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Palette.track, style: StrokeStyle(lineWidth: 5, lineCap: .round))

                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(Palette.progress, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Image(systemName: symbol)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.icon)
            }
            .frame(width: 43, height: 43)

            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.value.opacity(0.68))

                Text(valueText)
                    .font(.system(size: 22, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.value.opacity(metric == nil ? 0.60 : 1))
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)
        }
        .frame(height: 47)
        .scaleEffect(hovered ? 1.018 : 1, anchor: .leading)
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.18)) { hovered = inside }
        }
        .onAppear { updateProgress() }
        .onChange(of: metric) { _, _ in updateProgress() }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(valueText)
    }

    private var valueText: String {
        if loading { return "···" }
        guard let metric else { return "—" }
        return "\(Int(metric.remainingPercent.rounded()))%"
    }

    private var helpText: String {
        guard let metric else {
            return language == .chinese
                ? "\(title)：\(language.noAvailableRecord)"
                : "\(title): \(language.noAvailableRecord)"
        }
        let value = Int(metric.remainingPercent.rounded())
        guard let reset = metric.resetsAt else {
            return language == .chinese
                ? "\(title)：\(language.remaining) \(value)%"
                : "\(title): \(value)% \(language.remaining)"
        }
        return language == .chinese
            ? "\(title)：\(language.remaining) \(value)%，\(reset.formatted(date: .abbreviated, time: .shortened)) \(language.resets)"
            : "\(title): \(value)% \(language.remaining), \(language.resets) \(reset.formatted(date: .abbreviated, time: .shortened))"
    }

    private func updateProgress() {
        let target = (metric?.remainingPercent ?? 0) / 100
        if reduceMotion {
            animatedProgress = target
        } else {
            animatedProgress = 0
            withAnimation(.easeOut(duration: 0.72)) {
                animatedProgress = target
            }
        }
    }
}

private enum Palette {
    static let track = Color(red: 0.48, green: 0.73, blue: 0.52).opacity(0.31)
    static let progress = Color(red: 0.86, green: 0.95, blue: 0.87).opacity(0.98)
    static let icon = Color(red: 0.73, green: 0.87, blue: 0.75).opacity(0.95)
    static let value = Color(red: 0.79, green: 0.90, blue: 0.81)
}
