import Foundation

actor CodexUsageReader {
    private struct CachedSessionFile {
        let modified: Date
        let size: Int
        let metrics: [QuotaMetric]
    }

    private let codexDirectory: URL
    private let now: @Sendable () -> Date
    private var fileCache: [URL: CachedSessionFile] = [:]

    init(
        codexDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.codexDirectory = codexDirectory
        self.now = now
    }

    func read() -> UsageSnapshot {
        let readDate = now()
        let candidates = readRecentRateLimits()

        let fiveHour = freshestMetric(
            minutes: 300,
            in: candidates,
            noOlderThan: 12 * 60 * 60,
            relativeTo: readDate
        )
        let weekly = freshestMetric(
            minutes: 10_080,
            in: candidates,
            noOlderThan: 8 * 24 * 60 * 60,
            relativeTo: readDate
        )

        return UsageSnapshot(
            fiveHour: fiveHour,
            weekly: weekly,
            readAt: readDate
        )
    }

    private func freshestMetric(
        minutes: Int,
        in candidates: [QuotaMetric],
        noOlderThan maximumAge: TimeInterval,
        relativeTo readDate: Date
    ) -> QuotaMetric? {
        candidates
            .filter {
                $0.windowMinutes == minutes &&
                $0.limitID == "codex" &&
                readDate.timeIntervalSince($0.capturedAt) <= maximumAge
            }
            .max(by: { $0.capturedAt < $1.capturedAt })
    }

    private func readRecentRateLimits() -> [QuotaMetric] {
        let sessionsDirectory = codexDirectory.appendingPathComponent("sessions", isDirectory: true)
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .fileSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [(url: URL, modified: Date, size: Int)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            files.append((
                url,
                values.contentModificationDate ?? .distantPast,
                values.fileSize ?? 0
            ))
        }

        let recentFiles = files
            .sorted(by: { $0.modified > $1.modified })
            .prefix(64)

        let activeURLs = Set(recentFiles.map(\.url))
        fileCache = fileCache.filter { activeURLs.contains($0.key) }

        return recentFiles.flatMap { file in
            if let cached = fileCache[file.url],
               cached.modified == file.modified,
               cached.size == file.size {
                return cached.metrics
            }

            let metrics = metricsFromTail(of: file.url)
            fileCache[file.url] = CachedSessionFile(
                modified: file.modified,
                size: file.size,
                metrics: metrics
            )
            return metrics
        }
    }

    private func metricsFromTail(of fileURL: URL) -> [QuotaMetric] {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return [] }
        defer { try? handle.close() }

        let tailSize: UInt64 = 768 * 1_024
        let fileSize = (try? handle.seekToEnd()) ?? 0
        let start = fileSize > tailSize ? fileSize - tailSize : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return [] }

        var results: [QuotaMetric] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)

        for line in lines.reversed() {
            guard line.contains("\"rate_limits\"") else { continue }
            guard let lineData = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = root["payload"] as? [String: Any],
                  let limits = payload["rate_limits"] as? [String: Any],
                  let limitID = limits["limit_id"] as? String else { continue }

            let capturedAt = Self.parseTimestamp(root["timestamp"]) ??
                (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ??
                .distantPast

            for key in ["primary", "secondary"] {
                guard let window = limits[key] as? [String: Any],
                      let used = Self.doubleValue(window["used_percent"]),
                      let minutes = Self.intValue(window["window_minutes"]) else { continue }

                let resetDate = Self.doubleValue(window["resets_at"]).map(Date.init(timeIntervalSince1970:))
                results.append(QuotaMetric(
                    limitID: limitID,
                    usedPercent: used,
                    windowMinutes: minutes,
                    resetsAt: resetDate,
                    capturedAt: capturedAt
                ))
            }

            // Rate-limit events repeat frequently. A few distinct recent events per file are enough.
            if results.count >= 6 { break }
        }

        return results
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}
