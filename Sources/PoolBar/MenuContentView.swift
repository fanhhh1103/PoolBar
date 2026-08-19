import SwiftUI
import PoolBarCore

struct MenuContentView: View {
    @ObservedObject var monitor: PoolMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("额度水位").font(.headline)

            PoolRow(status: monitor.codex, subtitle: "Codex CLI 周窗口")
            Divider()
            PoolRow(status: monitor.grok, subtitle: "Grok Build CLI")
            Divider()
            PoolRow(status: monitor.cursor, subtitle: "Cursor Models（Grok / Composer / Auto）")
            Divider()
            PoolRow(status: monitor.cursorAPI, subtitle: "Other Models（按 API 价），不进摊平")

            Divider()
            balanceHint

            HStack {
                Button(monitor.isRefreshing ? "刷新中…" : "立即刷新") { monitor.refreshNow() }
                    .disabled(monitor.isRefreshing)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(width: 360)
    }

    /// 摊平结论: 哪个池最该用、哪个最该省。和 quota.py status 末尾那句一致。
    @ViewBuilder
    private var balanceHint: some View {
        let ranked = monitor.pools.compactMap { p -> (PoolStatus, Double)? in
            guard let pace = p.pace else { return nil }
            return (p, pace)
        }
        if ranked.count > 1 {
            let cold = ranked.min { $0.1 < $1.1 }!
            let hot = ranked.max { $0.1 < $1.1 }!
            Text("摊平: 最该用 \(cold.0.name) (\(cold.0.paceLabel))，最该省 \(hot.0.name) (\(hot.0.paceLabel))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct PoolRow: View {
    let status: PoolStatus
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(status.name).font(.subheadline).bold()
                Spacer()
                Text(percentText).font(.system(.subheadline, design: .monospaced))
            }

            if !status.banned, let pct = status.usedPercent {
                ProgressView(value: min(pct, 100), total: 100)
                    .tint(color)
            }

            HStack(spacing: 6) {
                if !status.paceLabel.isEmpty {
                    Text(status.paceLabel)
                }
                if let binding = status.bindingLabel {
                    Text("· \(binding)")
                }
                if let resets = status.resetsAt {
                    Text("· 重置 \(resetText(resets))")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if let hint = status.dailyBurnHint {
                Text(hint.line)
                    .font(.caption2)
                    .foregroundStyle(hintColor(hint.tone))
            }

            if let detail = status.detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
            if let error = status.error {
                Text("⚠ \(error)").font(.caption2).foregroundStyle(.orange)
            }
            Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var percentText: String {
        if status.banned { return "封禁" }
        guard let v = status.usedPercent else { return "未知" }
        if v > 0, v < 1 { return String(format: "%.1f%%", v) }
        return String(format: "%.0f%%", v)
    }

    private var color: Color {
        switch status.levelColorName {
        case "red": return .red
        case "yellow": return .yellow
        case "green": return .green
        default: return .gray
        }
    }

    private func resetText(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd HH:mm"
        return fmt.string(from: date)
    }

    private func hintColor(_ tone: DailyBurn.Tone) -> Color {
        switch tone {
        case .neutral: return .secondary
        case .good: return .green
        case .warn: return .orange
        case .bad: return .red
        }
    }
}
