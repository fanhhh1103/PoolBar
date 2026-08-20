import Foundation
import Testing
import PoolBarCore

struct CodexQuotaTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let weekMinutes = 10_080.0
    let fiveHourMinutes = 300.0

    @Test func expiredWeeklySnapshotZerosUsageAndRollsReset() {
        let oldEnd = now.addingTimeInterval(-3600)
        let rl: [String: Any] = [
            "plan_type": "pro",
            "primary": [
                "used_percent": 87,
                "window_minutes": weekMinutes,
                "resets_at": oldEnd.timeIntervalSince1970,
            ] as [String: Any],
        ]
        let parsed = CodexQuota.parse(rateLimits: rl, snapshotAt: oldEnd.addingTimeInterval(-3 * 86_400), now: now)
        #expect(parsed.usedPercent == 0)
        #expect(parsed.stale == true)
        #expect(parsed.resetsAt == oldEnd.addingTimeInterval(weekMinutes * 60))
        #expect(parsed.label == "周窗口")
        #expect(parsed.detail?.contains("已结束周期") == true)
        #expect(parsed.detail?.contains("87%") == true)
        #expect(parsed.error == nil)
    }

    @Test func liveWeeklySnapshotKeepsUsage() {
        let end = now.addingTimeInterval(2 * 86_400)
        let rl: [String: Any] = [
            "plan_type": "plus",
            "primary": [
                "used_percent": 42.5,
                "window_minutes": weekMinutes,
                "resets_at": end.timeIntervalSince1970,
            ] as [String: Any],
        ]
        let parsed = CodexQuota.parse(rateLimits: rl, snapshotAt: now.addingTimeInterval(-60), now: now)
        #expect(parsed.usedPercent == 42.5)
        #expect(parsed.stale == false)
        #expect(parsed.resetsAt == end)
        #expect(parsed.detail == "套餐 plus")
    }

    @Test func prefersWeeklySecondaryOverFiveHourPrimary() {
        let rl: [String: Any] = [
            "primary": [
                "used_percent": 90,
                "window_minutes": fiveHourMinutes,
                "resets_at": now.addingTimeInterval(3 * 3600).timeIntervalSince1970,
            ] as [String: Any],
            "secondary": [
                "used_percent": 12,
                "window_minutes": weekMinutes,
                "resets_at": now.addingTimeInterval(4 * 86_400).timeIntervalSince1970,
            ] as [String: Any],
        ]
        let parsed = CodexQuota.parse(rateLimits: rl, snapshotAt: now, now: now)
        #expect(parsed.usedPercent == 12)
        #expect(parsed.stale == false)
        #expect(parsed.label == "周窗口")
        #expect(parsed.spanSeconds == weekMinutes * 60)
    }

    @Test func weeklyResetDoesNotKeepFiveHourPercent() {
        // 这就是「水位重置以后没更新」：primary 5h 还高，secondary 周窗口已过重置点。
        let rl: [String: Any] = [
            "primary": [
                "used_percent": 94,
                "window_minutes": fiveHourMinutes,
                "resets_at": now.addingTimeInterval(2 * 3600).timeIntervalSince1970,
            ] as [String: Any],
            "secondary": [
                "used_percent": 88,
                "window_minutes": weekMinutes,
                "resets_at": now.addingTimeInterval(-120).timeIntervalSince1970,
            ] as [String: Any],
        ]
        let parsed = CodexQuota.parse(rateLimits: rl, snapshotAt: now.addingTimeInterval(-86_400), now: now)
        #expect(parsed.usedPercent == 0)
        #expect(parsed.stale == true)
        #expect(parsed.label == "周窗口")
    }

    @Test func rollsForwardMultipleElapsedWindows() {
        let oldEnd = now.addingTimeInterval(-8 * 86_400)
        let span = weekMinutes * 60
        let rl: [String: Any] = [
            "primary": [
                "used_percent": 99,
                "window_minutes": weekMinutes,
                "resets_at": oldEnd.timeIntervalSince1970,
            ] as [String: Any],
        ]
        let parsed = CodexQuota.parse(rateLimits: rl, snapshotAt: oldEnd.addingTimeInterval(-3600), now: now)
        #expect(parsed.usedPercent == 0)
        #expect(parsed.resetsAt == oldEnd.addingTimeInterval(2 * span))
    }

    @Test func resetsInSecondsComputesAbsoluteReset() {
        let snapshot = now.addingTimeInterval(-60)
        let rl: [String: Any] = [
            "primary": [
                "used_percent": 6,
                "window_minutes": weekMinutes,
                "resets_in_seconds": 3_600,
            ] as [String: Any],
        ]
        let parsed = CodexQuota.parse(rateLimits: rl, snapshotAt: snapshot, now: now)
        #expect(parsed.usedPercent == 6)
        #expect(parsed.stale == false)
        #expect(parsed.resetsAt == snapshot.addingTimeInterval(3_600))
    }

    @Test func expiredResetsInSecondsZerosUsage() {
        let snapshot = now.addingTimeInterval(-8 * 86_400)
        let rl: [String: Any] = [
            "primary": [
                "used_percent": 70,
                "window_minutes": weekMinutes,
                "resets_in_seconds": 3_600,
            ] as [String: Any],
        ]
        let parsed = CodexQuota.parse(rateLimits: rl, snapshotAt: snapshot, now: now)
        #expect(parsed.usedPercent == 0)
        #expect(parsed.stale == true)
    }

    @Test func resetInstantCountsAsExpired() {
        let end = now
        let rl: [String: Any] = [
            "primary": [
                "used_percent": 100,
                "window_minutes": weekMinutes,
                "resets_at": end.timeIntervalSince1970,
            ] as [String: Any],
        ]
        let parsed = CodexQuota.parse(rateLimits: rl, snapshotAt: now.addingTimeInterval(-86_400), now: now)
        #expect(parsed.usedPercent == 0)
        #expect(parsed.stale == true)
        #expect(parsed.resetsAt == end.addingTimeInterval(weekMinutes * 60))
    }

    @Test func secondaryOnlyWeeklyIsAccepted() {
        let end = now.addingTimeInterval(86_400)
        let rl: [String: Any] = [
            "secondary": [
                "used_percent": 15,
                "window_minutes": weekMinutes,
                "resets_at": end.timeIntervalSince1970,
            ] as [String: Any],
        ]
        let parsed = CodexQuota.parse(rateLimits: rl, snapshotAt: now, now: now)
        #expect(parsed.usedPercent == 15)
        #expect(parsed.error == nil)
    }

    @Test func fiveHourOnlyKeepsShortLabel() {
        let rl: [String: Any] = [
            "primary": [
                "used_percent": 33,
                "window_minutes": fiveHourMinutes,
                "resets_at": now.addingTimeInterval(1800).timeIntervalSince1970,
            ] as [String: Any],
        ]
        let parsed = CodexQuota.parse(rateLimits: rl, snapshotAt: now, now: now)
        #expect(parsed.usedPercent == 33)
        #expect(parsed.label == "5h 闸门")
        #expect(parsed.stale == false)
    }

    @Test func extractSkipsNullRateLimits() {
        let obj: [String: Any] = [
            "timestamp": "2026-08-20T10:00:00Z",
            "payload": [
                "type": "token_count",
                "rate_limits": NSNull(),
            ] as [String: Any],
        ]
        #expect(CodexQuota.extractRateLimits(from: obj) == nil)
    }

    @Test func extractReadsPayloadRateLimits() {
        let obj: [String: Any] = [
            "timestamp": "2026-08-20T10:00:00Z",
            "payload": [
                "type": "token_count",
                "rate_limits": [
                    "primary": ["used_percent": 1, "window_minutes": weekMinutes] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
        ]
        let rl = CodexQuota.extractRateLimits(from: obj)
        #expect(rl != nil)
        #expect(CodexQuota.jsonNumber((rl?["primary"] as? [String: Any])?["used_percent"]) == 1)
    }

    @Test func extractReadsPayloadThatIsTheSnapshot() {
        let obj: [String: Any] = [
            "timestamp": "2026-08-20T10:00:00Z",
            "payload": [
                "type": "rate_limits_updated",
                "primary": ["used_percent": 8, "window_minutes": weekMinutes] as [String: Any],
            ] as [String: Any],
        ]
        #expect(CodexQuota.extractRateLimits(from: obj) != nil)
    }

    @Test func newerEventPrefersParsedDateOverString() {
        let older = CodexQuota.parseISO8601("2026-08-20T02:00:00+08:00")
        let newer = CodexQuota.parseISO8601("2026-08-20T02:00:00Z")
        #expect(older != nil && newer != nil)
        #expect(
            CodexQuota.isNewerEvent(
                timestamp: newer,
                timestampString: "2026-08-20T02:00:00Z",
                than: older,
                bestString: "2026-08-20T02:00:00+08:00"
            )
        )
        // 纯字符串比较会把 +08:00 判成更新（'+' > 'Z' 不一定，但时区混写不可靠）。
        #expect(
            CodexQuota.isNewerEvent(
                timestamp: older,
                timestampString: "2026-08-20T02:00:00+08:00",
                than: newer,
                bestString: "2026-08-20T02:00:00Z"
            ) == false
        )
    }

    @Test func missingWindowsError() {
        let parsed = CodexQuota.parse(rateLimits: ["plan_type": "pro"], snapshotAt: now, now: now)
        #expect(parsed.usedPercent == nil)
        #expect(parsed.error == "rate_limits 里没有 primary/secondary 窗口")
    }

    @Test func missingUsedPercentError() {
        let rl: [String: Any] = [
            "primary": [
                "window_minutes": weekMinutes,
                "resets_at": now.addingTimeInterval(86_400).timeIntervalSince1970,
            ] as [String: Any],
        ]
        let parsed = CodexQuota.parse(rateLimits: rl, snapshotAt: now, now: now)
        #expect(parsed.usedPercent == nil)
        #expect(parsed.error == "rate_limits 里没有 used_percent")
    }

    @Test func isoResetsAtString() {
        let end = "2026-08-27T12:00:00Z"
        let rl: [String: Any] = [
            "primary": [
                "used_percent": 5,
                "window_minutes": weekMinutes,
                "resets_at": end,
            ] as [String: Any],
        ]
        let parsed = CodexQuota.parse(
            rateLimits: rl,
            snapshotAt: CodexQuota.parseISO8601("2026-08-20T12:00:00Z"),
            now: CodexQuota.parseISO8601("2026-08-20T12:00:00Z")!
        )
        #expect(parsed.usedPercent == 5)
        #expect(parsed.resetsAt == CodexQuota.parseISO8601(end))
    }
}
