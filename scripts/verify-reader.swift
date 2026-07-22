import Foundation

@main
struct ReaderVerification {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexGaugeReaderVerification-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessions = root.appendingPathComponent("sessions/2026/07/21", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

        // The competing pool is newer and reports 0% used. It must not override the
        // main Codex account pool, which reports 72% used / 28% remaining.
        let fixture = """
        {"timestamp":"2026-07-21T14:21:30Z","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":72,"window_minutes":10080,"resets_at":1785070185},"secondary":{"used_percent":40,"window_minutes":300,"resets_at":1785000000}}}}
        {"timestamp":"2026-07-21T14:24:20Z","payload":{"type":"token_count","rate_limits":{"limit_id":"codex_bengalfox","primary":{"used_percent":0,"window_minutes":10080,"resets_at":1785248640},"secondary":{"used_percent":0,"window_minutes":300,"resets_at":1785248640}}}}
        """
        let rollout = sessions.appendingPathComponent("rollout.jsonl")
        try fixture.write(
            to: rollout,
            atomically: true,
            encoding: .utf8
        )

        guard let fixedNow = ISO8601DateFormatter().date(from: "2026-07-21T14:25:00Z") else {
            throw VerificationError.invalidFixtureDate
        }
        let reader = CodexUsageReader(codexDirectory: root, now: { fixedNow })
        let snapshot = await reader.read()

        guard snapshot.weekly?.remainingPercent == 28 else {
            throw VerificationError.unexpectedWeekly(snapshot.weekly?.remainingPercent)
        }
        guard snapshot.fiveHour?.remainingPercent == 60 else {
            throw VerificationError.unexpectedFiveHour(snapshot.fiveHour?.remainingPercent)
        }

        // A second read must invalidate the cached tail when Codex appends usage.
        let updatedFixture = "\n" + """
        {"timestamp":"2026-07-21T14:24:40Z","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":73,"window_minutes":10080,"resets_at":1785070185},"secondary":{"used_percent":41,"window_minutes":300,"resets_at":1785000000}}}}

        """
        let handle = try FileHandle(forWritingTo: rollout)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(updatedFixture.utf8))
        try handle.close()

        let updatedSnapshot = await reader.read()
        guard updatedSnapshot.weekly?.remainingPercent == 27 else {
            throw VerificationError.unexpectedWeekly(updatedSnapshot.weekly?.remainingPercent)
        }
        guard updatedSnapshot.fiveHour?.remainingPercent == 59 else {
            throw VerificationError.unexpectedFiveHour(updatedSnapshot.fiveHour?.remainingPercent)
        }

        print("PASS weekly=28→27% fiveHour=60→59% competing-pool-ignored cache-invalidated")
    }
}

private enum VerificationError: Error {
    case invalidFixtureDate
    case unexpectedWeekly(Double?)
    case unexpectedFiveHour(Double?)
}
