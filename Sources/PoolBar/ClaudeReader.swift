import Foundation
import Security

/// 对齐 claude-usage.py: 从钥匙串取 Claude Code 的 OAuth token, 调
/// api.anthropic.com/api/oauth/usage, 优先读权威的 `limits` 数组 (会漏看
/// weekly_scoped 就用顶层 five_hour/seven_day, 那会低估——已用 limits[] 修过一次了)。
///
/// 凭证纪律: token 只在内存里过一遍, 不写日志、不写磁盘、只发给它自己的签发方。
/// 首次运行系统会弹钥匙串访问确认, 这是正常的 ACL 行为, 点允许即可。
enum ClaudeReader {
    /// Claude is not shown in the menu yet. Keep the reader off the network.
    static let banned = true

    private static let keychainService = "Claude Code-credentials"
    private static let credsFile = ("~/.claude/.credentials.json" as NSString).expandingTildeInPath
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func read() async -> PoolStatus {
        if banned {
            var status = PoolStatus.empty("claude")
            status.banned = true
            status.detail = "账号不可用。不刷新 OAuth，不参与摊平"
            return status
        }
        var status = PoolStatus.empty("claude")
        guard let token = token() else {
            status.error = "拿不到 OAuth 凭证 (钥匙串 '\(keychainService)' 或 \(credsFile))"
            return status
        }

        var req = URLRequest(url: endpoint)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 20

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                status.error = "端点返回 HTTP \(code)" + (code == 401 ? " (凭证过期, 重新登录一次)" : "")
                return status
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                status.error = "响应不是 JSON"
                return status
            }
            apply(obj, to: &status)
        } catch {
            status.error = "请求失败: \(error.localizedDescription)"
        }
        return status
    }

    private static func apply(_ obj: [String: Any], to status: inout PoolStatus) {
        status.snapshotAt = Date()
        guard let limits = obj["limits"] as? [[String: Any]], !limits.isEmpty else {
            status.error = "响应里没有 limits 数组 —— 端点字段可能改了"
            return
        }

        // 三个窗口性质不同, 各自成一档, **不再取 max 合成一个数**:
        //   session      5 小时闸门, 一天重置约 5 次, 烧速波动大 → 不参与摊平
        //   weekly_all   总周额度 → 这才是跟 codex/grok 可比的摊平判据
        //   weekly_scoped(模型) 某模型专属周额度 → 它紧而 weekly_all 松时,
        //                换 Claude 模型就能绕开, 比跨池更省
        var session: QuotaWindow?
        var weeklyAll: QuotaWindow?
        var scoped: [QuotaWindow] = []

        for item in limits {
            guard let percent = (item["percent"] as? NSNumber)?.doubleValue else { continue }
            let kind = (item["kind"] as? String) ?? (item["group"] as? String) ?? "limit"
            let resets = parseISO8601(item["resets_at"] as? String ?? "")
            let isSession = kind.hasPrefix("session")
            let span: TimeInterval = isSession ? 5 * 3600 : 7 * 86400

            if isSession {
                session = QuotaWindow(label: "5h 闸门", usedPercent: percent,
                                      resetsAt: resets, spanSeconds: span, isGate: true)
            } else if kind == "weekly_all" {
                weeklyAll = QuotaWindow(label: "周 · 全部", usedPercent: percent,
                                        resetsAt: resets, spanSeconds: span)
            } else if kind.hasPrefix("weekly_scoped") {
                let model = ((item["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                scoped.append(QuotaWindow(label: "周 · \(model ?? "?")", usedPercent: percent,
                                          resetsAt: resets, spanSeconds: span))
            }
        }

        var windows: [QuotaWindow] = []
        if let s = session { windows.append(s) }
        if let w = weeklyAll { windows.append(w) }
        windows.append(contentsOf: scoped.sorted { $0.usedPercent > $1.usedPercent })

        guard !windows.isEmpty else {
            status.error = "limits 数组里没有可用的 percent 字段"
            return
        }
        status.windows = windows
        // 摊平判据锁定总周额度; 拿不到就退回第一个非闸门窗口, 绝不用 5 小时窗口。
        status.balanceIndex = windows.firstIndex { $0.label == "周 · 全部" }
            ?? windows.firstIndex { !$0.isGate }
    }

    // MARK: - 凭证

    private static func token() -> String? {
        keychainToken() ?? fileToken()
    }

    private static func keychainToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let raw = String(data: data, encoding: .utf8) else { return nil }
        return extractToken(raw)
    }

    private static func fileToken() -> String? {
        guard let data = FileManager.default.contents(atPath: credsFile),
              let raw = String(data: data, encoding: .utf8) else { return nil }
        return extractToken(raw)
    }

    /// 凭证可能是裸 token, 也可能是 JSON —— 与 claude-usage.py 的 _extract_token 对齐。
    private static func extractToken(_ raw: String) -> String? {
        let blob = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard blob.hasPrefix("{") else { return blob.isEmpty ? nil : blob }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(blob.utf8)) as? [String: Any] else {
            return nil
        }
        if let nested = obj["claudeAiOauth"] as? [String: Any] {
            if let t = nested["accessToken"] as? String { return t }
            if let t = nested["access_token"] as? String { return t }
        }
        if let t = obj["accessToken"] as? String { return t }
        if let t = obj["access_token"] as? String { return t }
        return nil
    }
}
