import Foundation

/// Codex `payload.rate_limits` 快照。会话日志只在发请求时追加，
/// 周窗口过了重置点以后，最后一条仍是旧周期的 used%，必须按 resets_at 作废。
///
/// Codex 可能同时报 5h primary + 7d secondary，也可能（2026-07-12 起）
/// 只把周窗口放在 primary。菜单栏 Cxx /「周窗口」锁定长周期，不用 5h。
public enum CodexQuota {
    public static let longWindowMinimum: TimeInterval = 36 * 3600

    public struct Parsed: Equatable, Sendable {
        public var usedPercent: Double?
        public var resetsAt: Date?
        public var spanSeconds: TimeInterval?
        public var label: String
        public var detail: String?
        public var snapshotAt: Date?
        public var stale: Bool
        public var error: String?

        public init(
            usedPercent: Double? = nil,
            resetsAt: Date? = nil,
            spanSeconds: TimeInterval? = nil,
            label: String = "周窗口",
            detail: String? = nil,
            snapshotAt: Date? = nil,
            stale: Bool = false,
            error: String? = nil
        ) {
            self.usedPercent = usedPercent
            self.resetsAt = resetsAt
            self.spanSeconds = spanSeconds
            self.label = label
            self.detail = detail
            self.snapshotAt = snapshotAt
            self.stale = stale
            self.error = error
        }
    }

    /// 从一条会话 JSONL 对象取出非空 rate_limits（primary 或 secondary 即可）。
    public static func extractRateLimits(from object: [String: Any]) -> [String: Any]? {
        if let payload = object["payload"] as? [String: Any] {
            if let found = usable(payload["rate_limits"] as? [String: Any]) {
                return found
            }
            if let found = usable(payload) {
                return found
            }
        }
        if let found = usable(object["rate_limits"] as? [String: Any]) {
            return found
        }
        return usable(object)
    }

    public static func eventTimestamp(from object: [String: Any]) -> Date? {
        if let s = object["timestamp"] as? String { return parseISO8601(s) }
        if let s = object["ts"] as? String { return parseISO8601(s) }
        return nil
    }

    public static func eventTimestampString(from object: [String: Any]) -> String {
        (object["timestamp"] as? String) ?? (object["ts"] as? String) ?? ""
    }

    /// 两条事件谁更新。优先比解析后的 Date，避免 ISO 带/不带小数秒、时区写法把字符串比较弄反。
    public static func isNewerEvent(
        timestamp: Date?,
        timestampString: String,
        than best: Date?,
        bestString: String?
    ) -> Bool {
        if let timestamp, let best { return timestamp > best }
        if timestamp != nil, best == nil { return true }
        if timestamp == nil, best != nil { return false }
        guard let bestString else { return true }
        return timestampString > bestString
    }

    public static func parse(
        rateLimits: [String: Any],
        snapshotAt: Date?,
        now: Date = Date()
    ) -> Parsed {
        guard let window = pickBalanceWindow(from: rateLimits) else {
            return Parsed(error: "rate_limits 里没有 primary/secondary 窗口")
        }

        let rawUsed = jsonNumber(window["used_percent"])
        let span = spanSeconds(from: window)
        let rawResets = resolveResetsAt(window: window, snapshotAt: snapshotAt)
        let rolled = applyExpiry(usedPercent: rawUsed, resetsAt: rawResets, spanSeconds: span, now: now)

        let planType = rateLimits["plan_type"] as? String ?? "?"
        let credits = rateLimits["credits"] as? [String: Any]
        let balance = jsonNumber(credits?["balance"]) ?? 0
        let hasCredits = (credits?["has_credits"] as? Bool) ?? false
        let liveDetail = "套餐 \(planType)" + (hasCredits ? String(format: "  credits %.0f", balance) : "")

        return Parsed(
            usedPercent: rolled.usedPercent,
            resetsAt: rolled.resetsAt,
            spanSeconds: span,
            label: label(spanSeconds: span),
            detail: rolled.stale
                ? String(
                    format: "快照 %.0f%% 属于已结束周期, 按重置推定为 0%%, 需重新跑一次 Codex",
                    rawUsed ?? 0
                )
                : liveDetail,
            snapshotAt: snapshotAt,
            stale: rolled.stale,
            error: rolled.usedPercent == nil ? "rate_limits 里没有 used_percent" : nil
        )
    }

    public static func jsonNumber(_ value: Any?) -> Double? {
        if value is Bool { return nil }
        switch value {
        case let n as NSNumber:
            return n.doubleValue
        case let d as Double:
            return d
        case let f as Float:
            return Double(f)
        case let i as Int:
            return Double(i)
        case let i as Int64:
            return Double(i)
        case let u as UInt:
            return Double(u)
        case let s as String:
            return Double(s)
        default:
            return nil
        }
    }

    public static func parseISO8601(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    // MARK: - Windows

    static func pickBalanceWindow(from rateLimits: [String: Any]) -> [String: Any]? {
        let keys = ["primary", "secondary"]
        let candidates: [(dict: [String: Any], span: TimeInterval)] = keys.compactMap { key in
            guard let dict = rateLimits[key] as? [String: Any] else { return nil }
            return (dict, spanSeconds(from: dict) ?? 0)
        }
        guard !candidates.isEmpty else { return nil }
        let long = candidates.filter { $0.span >= longWindowMinimum }
        if let best = long.max(by: { $0.span < $1.span }) {
            return best.dict
        }
        return candidates.max(by: { $0.span < $1.span })?.dict
    }

    static func spanSeconds(from window: [String: Any]) -> TimeInterval? {
        guard let minutes = jsonNumber(window["window_minutes"])
            ?? jsonNumber(window["window_duration_mins"]),
            minutes > 0
        else { return nil }
        return minutes * 60
    }

    static func resolveResetsAt(window: [String: Any], snapshotAt: Date?) -> Date? {
        if let date = parseDateValue(window["resets_at"]) {
            return date
        }
        if let seconds = jsonNumber(window["resets_in_seconds"]), let snapshotAt {
            return snapshotAt.addingTimeInterval(seconds)
        }
        return nil
    }

    static func parseDateValue(_ value: Any?) -> Date? {
        if let n = jsonNumber(value) {
            // 秒级 epoch；若误写成毫秒（13 位），收到合理日期。
            let epoch = n > 1_000_000_000_000 ? n / 1000 : n
            return Date(timeIntervalSince1970: epoch)
        }
        if let s = value as? String {
            if let d = parseISO8601(s) { return d }
            if let n = Double(s) {
                let epoch = n > 1_000_000_000_000 ? n / 1000 : n
                return Date(timeIntervalSince1970: epoch)
            }
        }
        return nil
    }

    static func applyExpiry(
        usedPercent: Double?,
        resetsAt: Date?,
        spanSeconds: TimeInterval?,
        now: Date
    ) -> (usedPercent: Double?, resetsAt: Date?, stale: Bool) {
        guard let end = resetsAt, now >= end else {
            return (usedPercent, resetsAt, false)
        }
        var next = end
        if let spanSeconds, spanSeconds > 0 {
            let elapsed = now.timeIntervalSince(end)
            let cycles = floor(elapsed / spanSeconds) + 1
            next = end.addingTimeInterval(cycles * spanSeconds)
            if next <= now {
                next = next.addingTimeInterval(spanSeconds)
            }
        }
        return (0, next, true)
    }

    static func label(spanSeconds: TimeInterval?) -> String {
        guard let span = spanSeconds, span > 0 else { return "周窗口" }
        if span >= longWindowMinimum { return "周窗口" }
        let minutes = span / 60
        if abs(minutes - 300) < 2 { return "5h 闸门" }
        if minutes.truncatingRemainder(dividingBy: 1440) == 0 {
            return "\(Int(minutes / 1440)) 天"
        }
        if minutes.truncatingRemainder(dividingBy: 60) == 0 {
            return "\(Int(minutes / 60))h"
        }
        return "\(Int(minutes.rounded()))m"
    }

    private static func usable(_ rl: [String: Any]?) -> [String: Any]? {
        guard let rl, hasWindow(rl) else { return nil }
        return rl
    }

    private static func hasWindow(_ rl: [String: Any]) -> Bool {
        (rl["primary"] as? [String: Any]) != nil
            || (rl["secondary"] as? [String: Any]) != nil
    }
}
