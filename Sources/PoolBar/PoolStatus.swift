import Foundation
import PoolBarCore

/// 一个额度窗口。Claude 一个池里有好几个性质不同的窗口, 不能合成一个数字:
///   5 小时 session  = 短期闸门, 一天重置约 5 次
///   7 天 weekly_all = 总周额度, 才是跟 codex/grok 可比的摊平判据
///   7 天 weekly_scoped(模型) = 某模型专属周额度
struct QuotaWindow: Identifiable {
    let id = UUID()
    var label: String           // 展示名, 如 "5h 闸门" / "周 · 全部" / "周 · Fable"
    var usedPercent: Double
    var resetsAt: Date?
    var spanSeconds: TimeInterval?
    /// 这个窗口是不是「闸门」性质 —— 打满了此刻就发不出请求, 但很快自己会恢复。
    var isGate: Bool = false

    var elapsedFraction: Double? {
        guard let end = resetsAt, let span = spanSeconds, span > 0 else { return nil }
        let start = end.addingTimeInterval(-span)
        return min(max(Date().timeIntervalSince(start) / span, 0.01), 1.0)
    }

    /// 烧速。5 小时窗口的烧速波动极大, 只用于展示, 不参与跨池摊平。
    var pace: Double? {
        guard let e = elapsedFraction else { return nil }
        return usedPercent / (e * 100.0)
    }

    var paceLabel: String {
        guard let p = pace else { return "" }
        if p > DailyBurn.hotPace { return String(format: "🔥 %.1f×", p) }
        if p < DailyBurn.coldPace { return String(format: "❄ %.1f×", p) }
        return String(format: "匀速 %.1f×", p)
    }

    func dailyBurnHint(now: Date = Date()) -> DailyBurn.Hint? {
        DailyBurn.hint(
            usedPercent: usedPercent,
            resetsAt: resetsAt,
            spanSeconds: spanSeconds,
            isGate: isGate,
            now: now
        )
    }

    var levelColorName: String {
        if usedPercent >= 90 { return "red" }
        if usedPercent >= 70 { return "yellow" }
        return "green"
    }
}

/// 一个额度池在某一刻的读数。字段语义与 ~/.claude/orchestration/scripts/quota.py 对齐。
struct PoolStatus {
    let name: String            // "codex" / "claude" / "grok" / "cursor" / "cursor API"
    var windows: [QuotaWindow] = []
    /// 参与跨池摊平的那个窗口的下标。**必须是长周期窗口** (7天), 否则拿 5 小时窗口
    /// 去跟 codex 的 7 天窗口比烧速是胡算。
    var balanceIndex: Int?
    var detail: String?
    var snapshotAt: Date?
    var error: String?
    /// 池已下线 (目前只有 claude)。不参与摊平, UI 灰色, 不打网络。
    var banned: Bool = false

    static func empty(_ name: String) -> PoolStatus { PoolStatus(name: name) }

    /// 单窗口池 (codex / grok / cursor 各池)。span 用来算烧速。
    static func single(
        name: String,
        label: String,
        usedPercent: Double?,
        resetsAt: Date?,
        spanSeconds: TimeInterval?,
        detail: String? = nil,
        snapshotAt: Date? = nil,
        error: String? = nil
    ) -> PoolStatus {
        var status = PoolStatus.empty(name)
        status.detail = detail
        status.snapshotAt = snapshotAt
        status.error = error
        if let usedPercent {
            status.windows = [
                QuotaWindow(label: label, usedPercent: usedPercent,
                            resetsAt: resetsAt, spanSeconds: spanSeconds)
            ]
            status.balanceIndex = 0
        }
        return status
    }

    var balanceWindow: QuotaWindow? {
        guard let i = balanceIndex, windows.indices.contains(i) else { return windows.first }
        return windows[i]
    }

    /// 闸门窗口 (若有)。它单独判: 打满了此刻派不出去, 但等几小时就好, 不该改道跨池。
    var gateWindow: QuotaWindow? { windows.first { $0.isGate } }

    var usedPercent: Double? { balanceWindow?.usedPercent }
    var pace: Double? { banned ? nil : balanceWindow?.pace }
    var paceLabel: String { banned ? "" : (balanceWindow?.paceLabel ?? "") }
    var resetsAt: Date? { balanceWindow?.resetsAt }
    var bindingLabel: String? { balanceWindow?.label }
    var dailyBurnHint: DailyBurn.Hint? { banned ? nil : balanceWindow?.dailyBurnHint() }

    var levelColorName: String {
        if banned { return "gray" }
        guard let w = balanceWindow else { return "gray" }
        return w.levelColorName
    }
}
