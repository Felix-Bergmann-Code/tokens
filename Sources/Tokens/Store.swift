import AppKit
import Foundation
import SwiftUI

enum Period: String, CaseIterable, Identifiable {
    case today, week, month, all
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "7 Days"
        case .month: "30 Days"
        case .all: "All"
        }
    }

    var caption: String {
        switch self {
        case .today: "today"
        case .week: "last 7 days"
        case .month: "last 30 days"
        case .all: "all time"
        }
    }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case tokens, cost, icon
    var id: String { rawValue }
    var name: String {
        switch self {
        case .tokens: "Today's tokens"
        case .cost: "Today's API value"
        case .icon: "Icon only"
        }
    }
}

struct DayAgg {
    var total = Usage()
    var byProvider: [Provider: Usage] = [:]
    var bySource: [Source: Usage] = [:]
    var byModel: [String: Usage] = [:]
    var byHour: [Int: [Provider: Usage]] = [:]
}

struct ChartPoint: Identifiable {
    var date: Date
    var provider: Provider
    var tokens: Int
    var cost: Double
    var id: String { "\(date.timeIntervalSince1970)-\(provider.rawValue)" }
}

struct Insight: Identifiable {
    var symbol: String
    var text: String
    var tint: Color = .secondary
    var id: String { text }
}

struct PlanSummary {
    var provider: Provider
    var planName: String
    var monthlyPrice: Double
    var detected: Bool
    var value30d: Double
    var tokens30d: Int
    var valueMTD: Double
    var projectedMonth: Double
    var breakEvenDay: Date?

    var leverage: Double { monthlyPrice > 0 ? value30d / monthlyPrice : 0 }
    var effectivePerMTok: Double { tokens30d > 0 ? monthlyPrice / (Double(tokens30d) / 1e6) : 0 }
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var days: [String: DayAgg] = [:]
    @Published private(set) var isScanning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var hasLoaded = false

    @Published var menuBarStyle: MenuBarStyle = Store.setting("menuBarStyle", .tokens) {
        didSet { UserDefaults.standard.set(menuBarStyle.rawValue, forKey: "menuBarStyle") }
    }
    @Published var claudePlanSetting: ClaudePlan = Store.setting("claudePlan", .auto) {
        didSet { UserDefaults.standard.set(claudePlanSetting.rawValue, forKey: "claudePlan") }
    }
    @Published var chatgptPlanSetting: ChatGPTPlan = Store.setting("chatgptPlan", .auto) {
        didSet { UserDefaults.standard.set(chatgptPlanSetting.rawValue, forKey: "chatgptPlan") }
    }

    private static func setting<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
        UserDefaults.standard.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }

    /// Bumped on every update that came from new agent activity, to drive the live pulse.
    @Published private(set) var liveTick = 0
    @Published private(set) var isWatching = false

    private let scanner = UsageScanner()
    private var watcher: FolderWatcher?
    private var timer: Timer?
    private var pendingRefresh = false
    private let cal = Calendar.current

    init() {
        refresh()
        startWatching()
        // Safety net for missed events, and rolls "today" over at midnight.
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [scanner] _ in
            scanner.saveCache()
        }
    }

    /// Re-scans as soon as any agent writes to its session logs.
    private func startWatching() {
        let folders = scanner.watchedFolders()
        watcher = FolderWatcher(paths: folders, latency: 1.0) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        isWatching = !folders.isEmpty
    }

    func refresh(rebuild: Bool = false) {
        // Coalesce: if a scan is running, run exactly one more once it finishes.
        guard !isScanning else {
            pendingRefresh = true
            return
        }
        isScanning = true
        let scanner = scanner
        Task.detached(priority: .userInitiated) {
            if rebuild { scanner.resetCache() }
            let snap = scanner.scan { p in
                Task { @MainActor in self.progress = p }
            }
            let days = Self.index(snap.buckets)
            await MainActor.run {
                let changed = self.hasLoaded && self.snapshot.buckets.count > 0
                    && (days[Fmt.key(self.today)]?.total ?? Usage()) != (self.days[Fmt.key(self.today)]?.total ?? Usage())
                withAnimation(.snappy(duration: 0.4)) {
                    self.snapshot = snap
                    self.days = days
                    self.hasLoaded = true
                    if changed { self.liveTick += 1 }
                }
                self.isScanning = false
                self.progress = 1
                if self.pendingRefresh {
                    self.pendingRefresh = false
                    self.refresh()
                }
            }
        }
    }

    nonisolated private static func index(_ buckets: [Bucket]) -> [String: DayAgg] {
        var out: [String: DayAgg] = [:]
        for b in buckets {
            var d = out[b.day] ?? DayAgg()
            let p = b.source.provider
            d.total += b.usage
            d.byProvider[p, default: Usage()] += b.usage
            d.bySource[b.source, default: Usage()] += b.usage
            d.byModel[b.model, default: Usage()] += b.usage
            d.byHour[b.hour, default: [:]][p, default: Usage()] += b.usage
            out[b.day] = d
        }
        return out
    }

    // MARK: - Ranges

    var today: Date { cal.startOfDay(for: .now) }

    func dayKeys(_ period: Period) -> [String] {
        switch period {
        case .today: return [Fmt.key(today)]
        case .week: return lastDays(7)
        case .month: return lastDays(30)
        case .all: return days.keys.sorted()
        }
    }

    func lastDays(_ n: Int, endingDaysAgo offset: Int = 0) -> [String] {
        (0..<n).reversed().compactMap { i in
            cal.date(byAdding: .day, value: -(i + offset), to: today).map(Fmt.key)
        }
    }

    func total(_ keys: [String]) -> DayAgg {
        var agg = DayAgg()
        for k in keys {
            guard let d = days[k] else { continue }
            agg.total += d.total
            for (p, u) in d.byProvider { agg.byProvider[p, default: Usage()] += u }
            for (s, u) in d.bySource { agg.bySource[s, default: Usage()] += u }
            for (m, u) in d.byModel { agg.byModel[m, default: Usage()] += u }
            for (h, v) in d.byHour { for (p, u) in v { agg.byHour[h, default: [:]][p, default: Usage()] += u } }
        }
        return agg
    }

    func total(_ period: Period) -> DayAgg { total(dayKeys(period)) }

    /// The equivalent window just before `period`, for trend comparison.
    func previous(_ period: Period) -> DayAgg? {
        switch period {
        case .today: return total(lastDays(1, endingDaysAgo: 1))
        case .week: return total(lastDays(7, endingDaysAgo: 7))
        case .month: return total(lastDays(30, endingDaysAgo: 30))
        case .all: return nil
        }
    }

    func chartPoints(_ period: Period) -> [ChartPoint] {
        switch period {
        case .today:
            let d = days[Fmt.key(today)]
            return (0..<24).flatMap { h -> [ChartPoint] in
                let date = cal.date(byAdding: .hour, value: h, to: today)!
                return Provider.allCases.map { p in
                    let u = d?.byHour[h]?[p] ?? Usage()
                    return ChartPoint(date: date, provider: p, tokens: u.total, cost: u.cost)
                }
            }
        case .week, .month:
            return dayKeys(period).flatMap { k -> [ChartPoint] in
                let date = Fmt.date(k)!
                return Provider.allCases.map { p in
                    let u = days[k]?.byProvider[p] ?? Usage()
                    return ChartPoint(date: date, provider: p, tokens: u.total, cost: u.cost)
                }
            }
        case .all:
            // Weekly bins from the first day with data.
            guard let first = days.keys.min().flatMap(Fmt.date) else { return [] }
            var weeks: [Date: [Provider: Usage]] = [:]
            for (k, d) in days {
                guard let date = Fmt.date(k),
                      let wk = cal.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
                for (p, u) in d.byProvider { weeks[wk, default: [:]][p, default: Usage()] += u }
            }
            var points: [ChartPoint] = []
            var cursor = cal.dateInterval(of: .weekOfYear, for: first)!.start
            while cursor <= .now {
                for p in Provider.allCases {
                    let u = weeks[cursor]?[p] ?? Usage()
                    points.append(ChartPoint(date: cursor, provider: p, tokens: u.total, cost: u.cost))
                }
                cursor = cal.date(byAdding: .weekOfYear, value: 1, to: cursor)!
            }
            return points
        }
    }

    // MARK: - Months

    struct MonthRow: Identifiable {
        var month: Date
        var usage: Usage
        var byProvider: [Provider: Usage]
        var activeDays: Int
        var id: Date { month }
    }

    var months: [MonthRow] {
        var map: [Date: MonthRow] = [:]
        for (k, d) in days {
            guard let date = Fmt.date(k),
                  let m = cal.dateInterval(of: .month, for: date)?.start else { continue }
            var row = map[m] ?? MonthRow(month: m, usage: Usage(), byProvider: [:], activeDays: 0)
            row.usage += d.total
            for (p, u) in d.byProvider { row.byProvider[p, default: Usage()] += u }
            if d.total.total > 0 { row.activeDays += 1 }
            map[m] = row
        }
        return map.values.sorted { $0.month > $1.month }
    }

    // MARK: - Subscriptions

    var claudePlan: (plan: ClaudePlan, detected: Bool) {
        if claudePlanSetting != .auto { return (claudePlanSetting, false) }
        if let p = ClaudePlan.detect(rateTier: snapshot.claudeRateTier) { return (p, true) }
        return (.none, false)
    }

    var chatgptPlan: (plan: ChatGPTPlan, detected: Bool) {
        if chatgptPlanSetting != .auto { return (chatgptPlanSetting, false) }
        if let p = ChatGPTPlan.detect(planType: snapshot.codexLimits?.plan) { return (p, true) }
        return (.none, false)
    }

    func planSummary(_ provider: Provider) -> PlanSummary {
        let name: String, price: Double, detected: Bool
        switch provider {
        case .claude:
            let p = claudePlan
            (name, price, detected) = (p.plan.name, p.plan.monthlyPrice, p.detected)
        case .codex:
            let p = chatgptPlan
            (name, price, detected) = (p.plan.name, p.plan.monthlyPrice, p.detected)
        }
        let last30 = total(lastDays(30))
        let monthStart = cal.dateInterval(of: .month, for: .now)!.start
        let mtdKeys = lastDays(cal.dateComponents([.day], from: monthStart, to: today).day! + 1)
        let mtd = total(mtdKeys).byProvider[provider]?.cost ?? 0
        let daysInMonth = Double(cal.range(of: .day, in: .month, for: .now)!.count)
        let projected = mtd / Double(mtdKeys.count) * daysInMonth

        // First day this month where cumulative value passed the plan price.
        var breakEven: Date?
        if price > 0 {
            var cum = 0.0
            for k in mtdKeys {
                cum += days[k]?.byProvider[provider]?.cost ?? 0
                if cum >= price { breakEven = Fmt.date(k); break }
            }
        }
        return PlanSummary(provider: provider, planName: name, monthlyPrice: price, detected: detected,
                           value30d: last30.byProvider[provider]?.cost ?? 0,
                           tokens30d: last30.byProvider[provider]?.total ?? 0,
                           valueMTD: mtd, projectedMonth: projected, breakEvenDay: breakEven)
    }

    // MARK: - Menu bar

    var menuBarText: String {
        guard hasLoaded else { return "" }
        let t = days[Fmt.key(today)]?.total ?? Usage()
        switch menuBarStyle {
        case .tokens: return Fmt.tokens(t.total)
        case .cost: return Fmt.usdCompact(t.cost)
        case .icon: return ""
        }
    }

    // MARK: - Insights

    func insights(_ period: Period) -> [Insight] {
        var out: [Insight] = []
        let keys = dayKeys(period)
        let agg = total(keys)
        guard agg.total.total > 0 else { return out }

        // Pace for the calendar month.
        let monthStart = cal.dateInterval(of: .month, for: .now)!.start
        let elapsed = cal.dateComponents([.day], from: monthStart, to: today).day! + 1
        let mtd = total(lastDays(elapsed)).total.cost
        if mtd > 0 {
            let projected = mtd / Double(elapsed) * Double(cal.range(of: .day, in: .month, for: .now)!.count)
            let month = monthStart.formatted(.dateTime.month(.wide))
            out.append(Insight(symbol: "speedometer",
                               text: "On pace for \(Fmt.usd(projected, cents: false)) of API usage in \(month).",
                               tint: .orange))
        }

        // Peak day in range.
        if period != .today,
           let peak = keys.compactMap({ k in days[k].map { (k, $0.total) } }).max(by: { $0.1.total < $1.1.total }),
           let date = Fmt.date(peak.0) {
            out.append(Insight(symbol: "flame",
                               text: "Biggest day: \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) with \(Fmt.tokens(peak.1.total)) tokens (\(Fmt.usd(peak.1.cost, cents: false))).",
                               tint: .red))
        }

        // Caching.
        if agg.total.totalInput > 0 {
            let share = Double(agg.total.cacheRead) / Double(agg.total.totalInput) * 100
            out.append(Insight(symbol: "memorychip",
                               text: "\(Fmt.percent(share)) of input was served from cache, which saved \(Fmt.usd(agg.total.cacheSavings, cents: false)) vs. uncached.",
                               tint: .teal))
        }

        // Top model by cost.
        if let top = agg.byModel.max(by: { $0.value.cost < $1.value.cost }), agg.total.cost > 0 {
            let share = top.value.cost / agg.total.cost * 100
            out.append(Insight(symbol: "cpu",
                               text: "\(top.key) drove \(Fmt.percent(share)) of the cost.",
                               tint: .purple))
        }

        // Output in human terms (≈ 100k tokens per novel).
        let novels = Double(agg.total.output) / 100_000
        if novels >= 1 {
            out.append(Insight(symbol: "text.book.closed",
                               text: "Your agents wrote \(Fmt.tokens(agg.total.output)) output tokens, about \(Int(novels.rounded())) novels' worth.",
                               tint: .indigo))
        }

        // Streak.
        var streak = 0
        var cursor = today
        if (days[Fmt.key(cursor)]?.total.total ?? 0) == 0 { cursor = cal.date(byAdding: .day, value: -1, to: cursor)! }
        while (days[Fmt.key(cursor)]?.total.total ?? 0) > 0 {
            streak += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        if streak >= 2 {
            out.append(Insight(symbol: "bolt.fill", text: "\(streak)-day streak of agent sessions.", tint: .yellow))
        }

        // Busiest hour.
        if let hour = agg.byHour.max(by: { a, b in
            a.value.values.reduce(0) { $0 + $1.total } < b.value.values.reduce(0) { $0 + $1.total }
        })?.key {
            let label = hour == 0 ? "midnight" : hour < 12 ? "\(hour) am" : hour == 12 ? "noon" : "\(hour - 12) pm"
            let owl = hour >= 22 || hour < 5 ? " Night owl." : ""
            out.append(Insight(symbol: "clock", text: "Your busiest hour is around \(label).\(owl)", tint: .blue))
        }
        return out
    }

    // MARK: - Heatmap

    /// Daily totals for the last `weeks` full weeks, oldest first, aligned to week starts.
    func heatmap(weeks: Int) -> [[(date: Date, usage: Usage)?]] {
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)!.start
        let start = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)!
        return (0..<weeks).map { w in
            (0..<7).map { d in
                let date = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                if date > .now { return nil }
                return (date, days[Fmt.key(date)]?.total ?? Usage())
            }
        }
    }
}
