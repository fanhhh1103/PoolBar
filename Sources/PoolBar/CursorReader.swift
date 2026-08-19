import Foundation

/// Cursor Models / Other Models. Refresh is the bundled `cursor-usage.py`.
/// Cache lives in ~/Library/Caches/PoolBar/. Legacy orchestration cache is a fallback.
enum CursorReader {
    private static let cacheDir = ("~/Library/Caches/PoolBar" as NSString).expandingTildeInPath
    private static let cachePath = cacheDir + "/cursor-usage.json"
    private static let legacyCachePath = ("~/.claude/orchestration/cache/cursor-usage.json" as NSString)
        .expandingTildeInPath
    private static let ttl: TimeInterval = 300

    static func read(forceRefresh: Bool = false) -> (models: PoolStatus, api: PoolStatus) {
        if forceRefresh || cacheIsStale() {
            _ = runRefresh(force: forceRefresh)
        }
        return parseCache() ?? (
            missing("cursor"),
            missing("cursor API")
        )
    }

    private static func missing(_ name: String) -> PoolStatus {
        var s = PoolStatus.empty(name)
        s.error = "读不到 Cursor 用量。先在 Cursor 登录，再点立即刷新"
        return s
    }

    private static func cacheIsStale() -> Bool {
        guard let rec = loadCache(),
              let captured = rec["captured_at"] as? NSNumber
        else { return true }
        return Date().timeIntervalSince1970 - captured.doubleValue > ttl
    }

    private static func loadCache() -> [String: Any]? {
        for path in [cachePath, legacyCachePath] {
            guard let data = FileManager.default.contents(atPath: path),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            return obj
        }
        return nil
    }

    private static func parseCache() -> (PoolStatus, PoolStatus)? {
        guard let rec = loadCache() else { return nil }
        let start = epoch(rec["billing_cycle_start"])
        let end = epoch(rec["billing_cycle_end"])
        let span: TimeInterval? = {
            guard let start, let end, end > start else { return 30 * 86400 }
            return end.timeIntervalSince(start)
        }()
        let snap: Date? = {
            guard let n = rec["captured_at"] as? NSNumber else { return nil }
            return Date(timeIntervalSince1970: n.doubleValue)
        }()
        let membership = rec["membership"] as? String

        let modelsNode = rec["cursor_models"] as? [String: Any] ?? [:]
        let modelsPct = (modelsNode["used_percent"] as? NSNumber)?.doubleValue
        var modelsDetail = membership.map { "套餐 \($0)" } ?? "Cursor Models"
        if let msg = rec["display_auto"] as? String, !msg.isEmpty {
            modelsDetail += "  · \(msg)"
        }
        if let cents = modelsNode["list_price_cents"] as? NSNumber, cents.doubleValue > 0 {
            modelsDetail += String(format: "  折算标价 $%.2f", cents.doubleValue / 100)
        }
        let models = PoolStatus.single(
            name: "cursor",
            label: "Models",
            usedPercent: modelsPct,
            resetsAt: end,
            spanSeconds: span,
            detail: modelsDetail,
            snapshotAt: snap,
            error: modelsPct == nil ? "缓存里没有 autoPercentUsed" : nil
        )

        let apiNode = rec["cursor_api"] as? [String: Any] ?? [:]
        let apiPct = (apiNode["used_percent"] as? NSNumber)?.doubleValue
        var apiDetail = "Other Models"
        if let limit = apiNode["included_limit_cents"] as? NSNumber {
            apiDetail += String(format: "  included $%.0f", limit.doubleValue / 100)
        }
        if let od = apiNode["on_demand_enabled"] as? Bool {
            apiDetail += od ? "  按量开" : "  按量关"
        }
        if let msg = rec["display_api"] as? String, !msg.isEmpty {
            apiDetail += "  · \(msg)"
        }
        let api = PoolStatus.single(
            name: "cursor API",
            label: "API",
            usedPercent: apiPct,
            resetsAt: end,
            spanSeconds: span,
            detail: apiDetail,
            snapshotAt: snap,
            error: apiPct == nil ? "缓存里没有 apiPercentUsed" : nil
        )
        return (models, api)
    }

    private static func epoch(_ v: Any?) -> Date? {
        if let n = v as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }
        if let d = v as? Double { return Date(timeIntervalSince1970: d) }
        return nil
    }

    private static func scriptPath() -> String? {
        var candidates: [String] = []
        if let bundled = Bundle.main.path(forResource: "cursor-usage", ofType: "py") {
            candidates.append(bundled)
        }
        if let res = Bundle.main.resourcePath {
            candidates.append(res + "/cursor-usage.py")
        }

        var roots = [FileManager.default.currentDirectoryPath]
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        roots.append(exe.deletingLastPathComponent().path)
        for root in roots {
            var url = URL(fileURLWithPath: root)
            for _ in 0..<8 {
                candidates.append(url.appendingPathComponent("Scripts/cursor-usage.py").path)
                url.deleteLastPathComponent()
            }
        }
        candidates.append(
            ("~/.claude/orchestration/scripts/cursor-usage.py" as NSString).expandingTildeInPath
        )

        return candidates.first { FileManager.default.isReadableFile(atPath: $0) }
    }

    @discardableResult
    private static func runRefresh(force: Bool) -> Bool {
        guard let script = scriptPath() else { return false }
        try? FileManager.default.createDirectory(
            atPath: cacheDir,
            withIntermediateDirectories: true
        )

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var args = ["python3", script, "refresh"]
        if force { args.append("--force") }
        proc.arguments = args
        var env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? "/usr/bin:/bin"
        if !path.contains("/opt/homebrew/bin") {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + path
        }
        env["POOLBAR_CACHE_DIR"] = cacheDir
        proc.environment = env
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }
}
