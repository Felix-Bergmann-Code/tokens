import SwiftUI

@main
struct TokensApp: App {
    @StateObject private var store = Store()

    init() {
        let args = CommandLine.arguments
        if args.contains("--dump") { Self.dump() }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            MainActor.assumeIsolated { Snapshotter.run(dir: args[i + 1]) }
        }
    }

    /// `Tokens --dump [--rebuild]`: prints a daily summary to stdout and exits.
    private static func dump() {
        let scanner = UsageScanner()
        if CommandLine.arguments.contains("--rebuild") { scanner.resetCache() }
        let start = Date()
        let snap = scanner.scan { _ in }
        var days: [String: [Provider: Usage]] = [:]
        var bySource: [Source: Usage] = [:]
        for b in snap.buckets {
            days[b.day, default: [:]][b.source.provider, default: Usage()] += b.usage
            bySource[b.source, default: Usage()] += b.usage
        }
        print("day         claude tokens   claude $   codex tokens    codex $")
        for day in days.keys.sorted() {
            let c = days[day]?[.claude] ?? Usage(), x = days[day]?[.codex] ?? Usage()
            print(day.padding(toLength: 12, withPad: " ", startingAt: 0),
                  String(format: "%14d %10.2f %14d %10.2f", c.total, c.cost, x.total, x.cost))
        }
        for (s, u) in bySource.sorted(by: { $0.value.total > $1.value.total }) {
            print(s.label, Fmt.tokens(u.total), Fmt.usd(u.cost), "\(u.requests) calls")
        }
        print("limits:", snap.codexLimits.map { "\($0)" } ?? "none")
        print("claude tier:", snap.claudeRateTier ?? "none")
        print(String(format: "files: %d, %.1fs", snap.fileCount, Date().timeIntervalSince(start)))
        exit(0)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(store)
        } label: {
            MenuBarLabel()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let text = store.menuBarText
        HStack(spacing: 4) {
            Image(systemName: "circle.hexagongrid.fill")
            if !text.isEmpty {
                Text(text).monospacedDigit().contentTransition(.numericText())
            }
        }
    }
}
