import Foundation

/// 对齐 quota.py 的 read_grok_quota(): ~/.grok/logs/unified.jsonl 里
/// msg="billing: fetched credits config" 那行的 ctx.config.creditUsagePercent。
enum GrokReader {
    static func read() -> PoolStatus {
        var status = PoolStatus.empty("grok")
        let path = ("~/.grok/logs/unified.jsonl" as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            status.error = "无 ~/.grok/logs/unified.jsonl (跑一次 grok 就会生成)"
            return status
        }

        var lastRecord: [String: Any]?
        var lastTs: String?
        for line in text.split(separator: "\n") where line.contains("creditUsagePercent") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let ctx = obj["ctx"] as? [String: Any],
                  let cfg = ctx["config"] as? [String: Any],
                  cfg["creditUsagePercent"] != nil
            else { continue }
            lastRecord = cfg
            lastTs = obj["ts"] as? String
        }

        guard let cfg = lastRecord else {
            status.error = "日志里没有 billing 记录"
            return status
        }

        let rawUsed = (cfg["creditUsagePercent"] as? NSNumber)?.doubleValue ?? 0
        let periodStart = parseISO8601(cfg["billingPeriodStart"] as? String ?? "")
        let periodEnd = parseISO8601(cfg["billingPeriodEnd"] as? String ?? "")
        let span: TimeInterval? = {
            guard let periodStart, let periodEnd, periodEnd > periodStart else { return 7 * 86400 }
            return periodEnd.timeIntervalSince(periodStart)
        }()

        // 跨周期校验: 快照若早于当前周期开始, 说明已重置, 旧百分比作废。
        let stale = periodEnd.map { Date() > $0 } ?? false
        return PoolStatus.single(
            name: "grok",
            label: "周额度",
            usedPercent: stale ? 0 : rawUsed,
            resetsAt: periodEnd,
            spanSeconds: span,
            detail: stale
                ? String(format: "快照 %.0f%% 属于已结束周期, 按重置推定为 0%%, 需重新跑一次 grok", rawUsed)
                : nil,
            snapshotAt: parseISO8601(lastTs ?? "")
        )
    }
}
