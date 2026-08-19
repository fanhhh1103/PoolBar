import Foundation

/// 到重置日耗。数字来自已有 used% / resetsAt / span，不另记流水。
/// 达标口径与 quota.py 相同：pace = 已用% ÷ 时间过去%，0.75…1.25 算匀速。
public enum DailyBurn {
    public static let hotPace = 1.25
    public static let coldPace = 0.75
    public static let settleAfter: TimeInterval = 6 * 3600

    public enum Tone: Equatable, Sendable {
        case neutral
        case good
        case warn
        case bad
    }

    public enum Verdict: Equatable, Sendable {
        case justStarted
        case onTrack
        case behind
        case ahead
        case exhausted
        case endingSoon
    }

    public struct Hint: Equatable, Sendable {
        public var line: String
        public var verdict: Verdict
        public var tone: Tone
        public var neededDailyPercent: Double?
        public var actualDailyPercent: Double?
        public var remainingDays: Double?

        public init(
            line: String,
            verdict: Verdict,
            tone: Tone,
            neededDailyPercent: Double? = nil,
            actualDailyPercent: Double? = nil,
            remainingDays: Double? = nil
        ) {
            self.line = line
            self.verdict = verdict
            self.tone = tone
            self.neededDailyPercent = neededDailyPercent
            self.actualDailyPercent = actualDailyPercent
            self.remainingDays = remainingDays
        }
    }

    public static func hint(
        usedPercent: Double,
        resetsAt: Date?,
        spanSeconds: TimeInterval?,
        isGate: Bool,
        now: Date = Date()
    ) -> Hint? {
        guard !isGate, let resetsAt, let spanSeconds, spanSeconds >= 36 * 3600 else {
            return nil
        }

        let start = resetsAt.addingTimeInterval(-spanSeconds)
        let remaining = resetsAt.timeIntervalSince(now)
        let elapsed = now.timeIntervalSince(start)
        let totalDays = spanSeconds / 86_400

        if remaining <= 0 {
            return nil
        }

        if usedPercent >= 99.5 {
            return Hint(
                line: "额度已用尽，等重置",
                verdict: .exhausted,
                tone: .bad,
                remainingDays: remaining / 86_400
            )
        }

        let remainingDays = remaining / 86_400
        let elapsedDays = max(elapsed / 86_400, 1.0 / 24.0)
        let leftover = max(100 - usedPercent, 0)
        let evenDaily = 100 / max(totalDays, 0.01)
        let neededDaily = leftover / max(remainingDays, 1.0 / 24.0)
        let actualDaily = usedPercent / elapsedDays
        let elapsedFraction = min(max(elapsed / spanSeconds, 0.01), 1.0)
        let pace = usedPercent / (elapsedFraction * 100.0)
        // 达标对照「到重置每天还需」，不是整段匀速。剩得少时两个数会分开。
        let catchupRatio = neededDaily > 0.01 ? actualDaily / neededDaily : 1.0
        let judgeRatio = leftover < 8 && pace <= hotPace ? 1.0 : catchupRatio

        if elapsed < settleAfter {
            return Hint(
                line: "刚重置，这周期每天该 \(formatPercent(evenDaily))，还有 \(formatRemain(remainingDays))",
                verdict: .justStarted,
                tone: .neutral,
                neededDailyPercent: evenDaily,
                actualDailyPercent: usedPercent > 0 ? actualDaily : 0,
                remainingDays: remainingDays
            )
        }

        let tone = toneFor(pace: judgeRatio)
        let verdictLabel = label(for: judgeRatio)

        if remaining < 86_400 {
            return Hint(
                line: "距重置 \(formatRemain(remainingDays)) · 今天还需 \(formatPercent(leftover)) · \(verdictLabel)",
                verdict: .endingSoon,
                tone: tone,
                neededDailyPercent: leftover,
                actualDailyPercent: actualDaily,
                remainingDays: remainingDays
            )
        }

        let verdict: Verdict
        switch tone {
        case .good: verdict = .onTrack
        case .warn: verdict = .behind
        case .bad: verdict = .ahead
        case .neutral: verdict = .onTrack
        }

        return Hint(
            line: "到重置 \(formatRemain(remainingDays)) · 每天需 \(formatPercent(neededDaily)) · 现日均 \(formatPercent(actualDaily)) · \(verdictLabel)",
            verdict: verdict,
            tone: tone,
            neededDailyPercent: neededDaily,
            actualDailyPercent: actualDaily,
            remainingDays: remainingDays
        )
    }

    public static func toneFor(pace: Double) -> Tone {
        if pace > hotPace { return .bad }
        if pace < coldPace { return .warn }
        return .good
    }

    public static func label(for pace: Double) -> String {
        if pace > hotPace { return "未达标偏快" }
        if pace < coldPace { return "未达标偏慢" }
        return "达标"
    }

    public static func formatPercent(_ value: Double) -> String {
        let clamped = max(value, 0)
        if clamped < 9.95 {
            return String(format: "%.1f%%", clamped)
        }
        return String(format: "%.0f%%", clamped.rounded())
    }

    public static func formatRemain(_ days: Double) -> String {
        if days >= 1.95 {
            return String(format: "%.0f 天", days.rounded())
        }
        if days >= 1 {
            return String(format: "%.1f 天", days)
        }
        let hours = days * 24
        if hours >= 1.5 {
            return String(format: "%.0f 小时", hours.rounded())
        }
        if hours >= 1 {
            return String(format: "%.1f 小时", hours)
        }
        return "不到 1 小时"
    }
}
