import Foundation
import Combine

/// Quota hub. Codex / Grok read local logs. Cursor refreshes via bundled cursor-usage.py.
/// Claude is not shown. Balance uses Codex / Grok / Cursor Models.
@MainActor
final class PoolMonitor: ObservableObject {
    @Published var codex = PoolStatus.empty("codex")
    @Published var grok = PoolStatus.empty("grok")
    @Published var cursor = PoolStatus.empty("cursor")
    @Published var cursorAPI = PoolStatus.empty("cursor API")
    @Published var isRefreshing = false

    private var timer: Timer?

    /// 执行层摊平用的池。cursor API 不进这条链。
    var pools: [PoolStatus] { [codex, grok, cursor] }

    var hottest: PoolStatus? {
        pools.max { (a, b) in (a.usedPercent ?? -1) < (b.usedPercent ?? -1) }
    }

    func start() {
        refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(force: false) }
        }
    }

    func refreshNow() {
        refresh(force: true)
    }

    private static let debug = ProcessInfo.processInfo.environment["POOLBAR_DEBUG"] != nil

    private func log(_ p: PoolStatus) {
        guard Self.debug else { return }
        let pct = p.usedPercent.map { String(format: "%.1f%%", $0) } ?? "nil"
        FileHandle.standardError.write(
            "[poolbar] \(p.name) used=\(pct) pace=\(p.paceLabel) binding=\(p.bindingLabel ?? "-") err=\(p.error ?? "-") banned=\(p.banned)\n"
                .data(using: .utf8)!)
    }

    private func refresh(force: Bool) {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task.detached(priority: .utility) {
            let codexResult = CodexReader.read()
            let grokResult = GrokReader.read()
            let cursorPair = CursorReader.read(forceRefresh: force)
            await MainActor.run {
                self.codex = codexResult
                self.grok = grokResult
                self.cursor = cursorPair.models
                self.cursorAPI = cursorPair.api
                self.isRefreshing = false
                self.log(codexResult)
                self.log(grokResult)
                self.log(cursorPair.models)
                self.log(cursorPair.api)
            }
        }
    }
}
