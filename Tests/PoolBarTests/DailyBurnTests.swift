import Foundation
import Testing
import PoolBarCore

struct DailyBurnTests {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let week: TimeInterval = 7 * 86_400
    let month: TimeInterval = 30 * 86_400

    var weekEnd: Date { start.addingTimeInterval(week) }
    var monthEnd: Date { start.addingTimeInterval(month) }

    @Test func midwayOnTrack() {
        let now = start.addingTimeInterval(week / 2)
        let hint = DailyBurn.hint(
            usedPercent: 50,
            resetsAt: weekEnd,
            spanSeconds: week,
            isGate: false,
            now: now
        )
        #expect(hint?.verdict == .onTrack)
        #expect(hint?.tone == .good)
        #expect(abs((hint?.neededDailyPercent ?? 0) - (50 / 3.5)) < 0.05)
        #expect(abs((hint?.actualDailyPercent ?? 0) - (50 / 3.5)) < 0.05)
        #expect(hint?.line.contains("达标") == true)
        #expect(hint?.line.contains("每天需") == true)
        #expect(hint?.line.contains("现日均") == true)
    }

    @Test func midwayBehind() {
        let now = start.addingTimeInterval(week / 2)
        let hint = DailyBurn.hint(
            usedPercent: 20,
            resetsAt: weekEnd,
            spanSeconds: week,
            isGate: false,
            now: now
        )
        #expect(hint?.verdict == .behind)
        #expect(hint?.tone == .warn)
        #expect(hint?.line.contains("未达标偏慢") == true)
        #expect((hint?.neededDailyPercent ?? 0) > (hint?.actualDailyPercent ?? 0))
    }

    @Test func midwayAhead() {
        let now = start.addingTimeInterval(week / 2)
        let hint = DailyBurn.hint(
            usedPercent: 80,
            resetsAt: weekEnd,
            spanSeconds: week,
            isGate: false,
            now: now
        )
        #expect(hint?.verdict == .ahead)
        #expect(hint?.tone == .bad)
        #expect(hint?.line.contains("未达标偏快") == true)
    }

    @Test func justStartedDoesNotJudge() {
        let now = start.addingTimeInterval(2 * 3600)
        let hint = DailyBurn.hint(
            usedPercent: 0,
            resetsAt: weekEnd,
            spanSeconds: week,
            isGate: false,
            now: now
        )
        #expect(hint?.verdict == .justStarted)
        #expect(hint?.tone == .neutral)
        #expect(hint?.line.contains("刚重置") == true)
        #expect(hint?.line.contains("每天该") == true)
        #expect(hint?.line.contains("未达标") == false)
    }

    @Test func lastDayUsesTodayCopy() {
        let now = weekEnd.addingTimeInterval(-8 * 3600)
        let hint = DailyBurn.hint(
            usedPercent: 88,
            resetsAt: weekEnd,
            spanSeconds: week,
            isGate: false,
            now: now
        )
        #expect(hint?.verdict == .endingSoon)
        #expect(hint?.line.contains("今天还需") == true)
        #expect(hint?.line.contains("每天需") == false)
    }

    @Test func exhausted() {
        let now = start.addingTimeInterval(week / 2)
        let hint = DailyBurn.hint(
            usedPercent: 100,
            resetsAt: weekEnd,
            spanSeconds: week,
            isGate: false,
            now: now
        )
        #expect(hint?.verdict == .exhausted)
        #expect(hint?.line == "额度已用尽，等重置")
    }

    @Test func gateWindowHidden() {
        let now = start.addingTimeInterval(2 * 3600)
        let hint = DailyBurn.hint(
            usedPercent: 40,
            resetsAt: start.addingTimeInterval(5 * 3600),
            spanSeconds: 5 * 3600,
            isGate: true,
            now: now
        )
        #expect(hint == nil)
    }

    @Test func expiredWindowHidden() {
        let hint = DailyBurn.hint(
            usedPercent: 40,
            resetsAt: weekEnd,
            spanSeconds: week,
            isGate: false,
            now: weekEnd.addingTimeInterval(60)
        )
        #expect(hint == nil)
    }

    @Test func monthlyNeededDaily() {
        let now = start.addingTimeInterval(10 * 86_400)
        let hint = DailyBurn.hint(
            usedPercent: 10,
            resetsAt: monthEnd,
            spanSeconds: month,
            isGate: false,
            now: now
        )
        #expect(hint?.verdict == .behind)
        #expect(abs((hint?.neededDailyPercent ?? 0) - (90 / 20)) < 0.05)
        #expect(abs((hint?.actualDailyPercent ?? 0) - 1.0) < 0.05)
    }

    @Test func nearEndBehindWhenCatchupExceedsActual() {
        // 已用 75%，还剩 1.2 天：每天还需 ~21%，现日均 ~13% → 偏慢。
        // 整段烧速约 0.90，旧口径会误报达标。
        let now = weekEnd.addingTimeInterval(-1.2 * 86_400)
        let hint = DailyBurn.hint(
            usedPercent: 75,
            resetsAt: weekEnd,
            spanSeconds: week,
            isGate: false,
            now: now
        )
        #expect(hint?.verdict == .behind)
        #expect(abs((hint?.neededDailyPercent ?? 0) - (25 / 1.2)) < 0.2)
        #expect(hint?.line.contains("未达标偏慢") == true)
    }

    @Test func almostFinishedDoesNotNagAhead() {
        let now = weekEnd.addingTimeInterval(-1.2 * 86_400)
        let hint = DailyBurn.hint(
            usedPercent: 96,
            resetsAt: weekEnd,
            spanSeconds: week,
            isGate: false,
            now: now
        )
        #expect(hint?.verdict == .onTrack)
        #expect(hint?.line.contains("达标") == true)
    }

    @Test func missingResetHidden() {
        let hint = DailyBurn.hint(
            usedPercent: 40,
            resetsAt: nil,
            spanSeconds: week,
            isGate: false,
            now: start
        )
        #expect(hint == nil)
    }
}
