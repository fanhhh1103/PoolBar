import SwiftUI

@main
struct PoolBarApp {
    static func main() {
        // 隔离诊断入口: 只跑读数逻辑, 完全绕开 SwiftUI/AppKit 生命周期,
        // 用来区分卡死是出在文件读取本身还是 App 启动流程。
        if ProcessInfo.processInfo.environment["POOLBAR_CLI_TEST"] != nil {
            var t = Date()
            func lap(_ label: String) {
                print(String(format: "  [%@] %.2fs", label, -t.timeIntervalSinceNow))
                t = Date()
            }
            let codex = CodexReader.read()
            lap("codex.read")
            print("codex: used=\(codex.usedPercent ?? -1) err=\(codex.error ?? "-") hint=\(codex.dailyBurnHint?.line ?? "-")")
            let grok = GrokReader.read()
            lap("grok.read")
            print("grok: used=\(grok.usedPercent ?? -1) err=\(grok.error ?? "-") hint=\(grok.dailyBurnHint?.line ?? "-")")
            let cursor = CursorReader.read(forceRefresh: false)
            lap("cursor.read")
            print("cursor: used=\(cursor.models.usedPercent ?? -1) api=\(cursor.api.usedPercent ?? -1) err=\(cursor.models.error ?? "-") hint=\(cursor.models.dailyBurnHint?.line ?? "-") apiHint=\(cursor.api.dailyBurnHint?.line ?? "-")")
            exit(0)
        }
        PoolBarSwiftUIApp.main()
    }
}

struct PoolBarSwiftUIApp: App {
    @StateObject private var monitor = PoolMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(monitor: monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

/// 菜单栏常驻数字。C=codex G=grok M=Cursor Models。
struct MenuBarLabel: View {
    @ObservedObject var monitor: PoolMonitor

    var body: some View {
        Text(labelText)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .onAppear { monitor.start() }
    }

    private var labelText: String {
        func short(_ p: PoolStatus, _ tag: String) -> String {
            guard let v = p.usedPercent else { return "\(tag)–" }
            if v > 0, v < 1 { return "\(tag)<1" }
            return "\(tag)\(Int(v.rounded()))"
        }
        var parts = [
            short(monitor.codex, "C"),
            short(monitor.grok, "G"),
            short(monitor.cursor, "M"),
        ]
        if let api = monitor.cursorAPI.usedPercent, api >= 1 {
            parts.append(short(monitor.cursorAPI, "P"))
        }
        return parts.joined(separator: " ")
    }
}
