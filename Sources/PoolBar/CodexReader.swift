import Foundation
import PoolBarCore

/// 扫 ~/.codex/sessions/**/*.jsonl, 取 mtime 最新的若干个文件里最新一条非空 rate_limits。
/// 窗口选用 / 过期清零在 CodexQuota，避免重置后仍钉死旧周期 used%。
enum CodexReader {
    static func read() -> PoolStatus {
        var status = PoolStatus.empty("codex")
        let sessionsDir = ("~/.codex/sessions" as NSString).expandingTildeInPath
        let sessionsURL = URL(fileURLWithPath: sessionsDir)

        // subpathsOfDirectory + attributesOfItem(每个文件单独 stat) 在 3000+ 文件的
        // 会话目录上实测要 12+ 秒、吃满一个核 —— 这正是要避免的"卡"。改用
        // FileManager.enumerator 配 includingPropertiesForKeys, 它会用一次批量
        // getattrlistbulk 预取 mtime, 不必逐文件再单独系统调用。
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            status.error = "无 ~/.codex/sessions 目录"
            return status
        }

        var scored: [(URL, Date)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let mtime = values.contentModificationDate
            else { continue }
            scored.append((url, mtime))
        }
        let ranked = scored
            .sorted { $0.1 > $1.1 }
            .prefix(40)
            .map { ($0.0.path, $0.1) }

        var newestDate: Date?
        var newestTsString: String?
        var newestPayload: [String: Any]?

        // 会话文件是追加写的日志, 我们只要「最后一条」rate_limits 事件, 它几乎总在
        // 文件尾部。实测最大文件 74MB, 若整份读入内存+UTF8 解码+split 要 9+ 秒;
        // 只读最后 2MB 尾窗口 (已验证 40 个真实文件里零漏检) 就够。
        let tailWindow: UInt64 = 2 * 1024 * 1024
        for (path, _) in ranked {
            guard let fh = FileHandle(forReadingAtPath: path) else { continue }
            defer { try? fh.close() }
            let fileSize = (try? fh.seekToEnd()) ?? 0
            let start = fileSize > tailWindow ? fileSize - tailWindow : 0
            try? fh.seek(toOffset: start)
            guard let data = try? fh.readToEnd(), let text = String(data: data, encoding: .utf8) else { continue }

            var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            if start > 0, !lines.isEmpty { lines.removeFirst() }  // 首行可能被从中间截断

            for line in lines where line.contains("rate_limits") {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let rl = CodexQuota.extractRateLimits(from: obj)
                else { continue }
                let ts = CodexQuota.eventTimestamp(from: obj)
                let tsString = CodexQuota.eventTimestampString(from: obj)
                if CodexQuota.isNewerEvent(
                    timestamp: ts,
                    timestampString: tsString,
                    than: newestDate,
                    bestString: newestTsString
                ) {
                    newestDate = ts
                    newestTsString = tsString
                    newestPayload = rl
                }
            }
        }

        guard let rl = newestPayload else {
            status.error = "会话日志里没有 rate_limits 记录"
            return status
        }

        let snapshotAt = newestDate ?? CodexQuota.parseISO8601(newestTsString ?? "")
        let parsed = CodexQuota.parse(rateLimits: rl, snapshotAt: snapshotAt)
        return PoolStatus.single(
            name: "codex",
            label: parsed.label,
            usedPercent: parsed.usedPercent,
            resetsAt: parsed.resetsAt,
            spanSeconds: parsed.spanSeconds,
            detail: parsed.detail,
            snapshotAt: parsed.snapshotAt,
            error: parsed.error
        )
    }
}

/// 兼容带/不带小数秒的 ISO8601 时间戳, 与 claude-usage.py 里的 iso_to_epoch 同样宽容。
func parseISO8601(_ s: String) -> Date? {
    CodexQuota.parseISO8601(s)
}
