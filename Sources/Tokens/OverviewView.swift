import Charts
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var store: Store
    @AppStorage("period") private var period: Period = .week
    @AppStorage("chartMetric") private var showCost = false
    @State private var selectedDate: Date?

    var body: some View {
        let agg = store.total(period)
        let prev = store.previous(period)

        VStack(spacing: 12) {
            GlassSegmented(items: Period.allCases, selection: $period, title: \.title, compact: true)
            hero(agg, prev)
            chartCard
            sources(agg)
            models(agg)
            insights
        }
        .onChange(of: period) { selectedDate = nil }
    }

    // MARK: Hero

    private func hero(_ agg: DayAgg, _ prev: DayAgg?) -> some View {
        Card {
            SectionLabel(text: "Tokens · \(period.caption)")
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.tokens(agg.total.total))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                if let prev { TrendBadge(current: Double(agg.total.total), previous: Double(prev.total.total)) }
            }
            HStack(spacing: 6) {
                Text(Fmt.usd(agg.total.cost))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("at API prices")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(agg.total.requests.formatted()) calls")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            SplitBar(parts: Provider.allCases.map { ($0.color, Double(agg.byProvider[$0]?.total ?? 0)) })
                .padding(.top, 2)
            HStack(spacing: 14) {
                ForEach(Provider.allCases.filter { agg.total.total == 0 || (agg.byProvider[$0]?.total ?? 0) > 0 }) { p in
                    let u = agg.byProvider[p] ?? Usage()
                    LegendDot(color: p.color, label: "\(p.name) \(Fmt.tokens(u.total)) · \(Fmt.usdCompact(u.cost))")
                }
            }
            tokenMix(agg.total)
        }
    }

    private func tokenMix(_ u: Usage) -> some View {
        HStack(spacing: 0) {
            mixCell("Input", u.input)
            mixCell("Cache write", u.cacheWrite)
            mixCell("Cache read", u.cacheRead)
            mixCell("Output", u.output)
        }
        .padding(.top, 4)
    }

    private func mixCell(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 9.5)).foregroundStyle(.tertiary)
            Text(Fmt.tokens(value)).font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Chart

    private var chartCard: some View {
        let points = store.chartPoints(period)
        let unit: Calendar.Component = period == .today ? .hour : period == .all ? .weekOfYear : .day
        let selected = selectedDate.flatMap { d in
            points.filter { Calendar.current.isDate($0.date, equalTo: d, toGranularity: unit) }
        }

        return Card {
            HStack {
                SectionLabel(text: period == .today ? "By hour" : period == .all ? "By week" : "By day")
                Spacer()
                GlassSegmented(items: [false, true].map(MetricOption.init), selection: Binding(
                    get: { MetricOption(cost: showCost) }, set: { showCost = $0.cost }
                ), title: { $0.cost ? "$" : "Tokens" }, compact: true)
                .frame(width: 110)
            }

            ZStack(alignment: .topLeading) {
                Chart(points) { pt in
                    BarMark(
                        x: .value("Date", pt.date, unit: unit),
                        y: .value(showCost ? "USD" : "Tokens", showCost ? pt.cost : Double(pt.tokens))
                    )
                    .foregroundStyle(by: .value("Provider", pt.provider.name))
                    .cornerRadius(3)
                    .opacity(selectedDate == nil || selected?.first.map { Calendar.current.isDate($0.date, equalTo: pt.date, toGranularity: unit) } == true ? 1 : 0.35)
                }
                .chartForegroundStyleScale([Provider.claude.name: Provider.claude.color.gradient,
                                            Provider.codex.name: Provider.codex.color.gradient])
                .chartLegend(.hidden)
                .chartXSelection(value: $selectedDate)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                guard case .active(let loc) = phase, let plot = proxy.plotFrame else {
                                    selectedDate = nil
                                    return
                                }
                                selectedDate = proxy.value(atX: loc.x - geo[plot].origin.x, as: Date.self)
                            }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                            .foregroundStyle(.primary.opacity(0.12))
                        AxisValueLabel {
                            if let d = v.as(Double.self) {
                                Text(showCost ? Fmt.usdCompact(d) : Fmt.tokens(Int(d)))
                                    .font(.system(size: 9))
                            }
                        }
                    }
                }
                .chartXAxis { xAxis }
                .frame(height: 150)

                if let selected, let first = selected.first {
                    let tokens = selected.reduce(0) { $0 + $1.tokens }
                    let cost = selected.reduce(0) { $0 + $1.cost }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(label(for: first.date))
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        Text("\(Fmt.tokens(tokens)) · \(Fmt.usd(cost))")
                            .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .rect(cornerRadius: 10))
                    .allowsHitTesting(false)
                }
            }
        }
    }

    @AxisContentBuilder private var xAxis: some AxisContent {
        switch period {
        case .today:
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisValueLabel(format: .dateTime.hour(), centered: false).font(.system(size: 9))
            }
        case .week:
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true).font(.system(size: 9))
            }
        case .month:
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: false).font(.system(size: 9))
            }
        case .all:
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: false).font(.system(size: 9))
            }
        }
    }

    private func label(for date: Date) -> String {
        switch period {
        case .today: date.formatted(.dateTime.hour())
        case .all: "Week of " + date.formatted(.dateTime.month(.abbreviated).day())
        default: date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
    }

    // MARK: Sources

    private func sources(_ agg: DayAgg) -> some View {
        let rows = Source.allCases
            .map { ($0, agg.bySource[$0] ?? Usage()) }
            .filter { $0.1.total > 0 }
            .sorted { $0.1.total > $1.1.total }
        let maxTokens = Double(rows.first?.1.total ?? 1)

        return Card {
            SectionLabel(text: "Agents")
            if rows.isEmpty {
                Text("No agent activity \(period.caption).")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.0) { source, u in
                VStack(spacing: 5) {
                    HStack(spacing: 8) {
                        Image(systemName: source.symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(source.provider.color)
                            .frame(width: 22, height: 22)
                            .background(source.provider.color.opacity(0.14), in: .rect(cornerRadius: 6))
                        Text(source.label).font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(Fmt.tokens(u.total))
                            .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text(Fmt.usdCompact(u.cost))
                            .font(.system(size: 11, design: .rounded)).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                    GeometryReader { geo in
                        Capsule().fill(source.provider.color.opacity(0.75).gradient)
                            .frame(width: max(4, geo.size.width * Double(u.total) / maxTokens))
                    }
                    .frame(height: 3)
                    .padding(.leading, 30)
                }
            }
        }
    }

    // MARK: Models

    private func models(_ agg: DayAgg) -> some View {
        let rows = agg.byModel.sorted { $0.value.cost > $1.value.cost }.prefix(5)
        let totalCost = max(agg.total.cost, 0.0001)
        return Group {
            if !rows.isEmpty {
                Card {
                    SectionLabel(text: "Models", trailing: "share of API value")
                    ForEach(Array(rows), id: \.key) { model, u in
                        HStack {
                            Circle()
                                .fill((model.hasPrefix("claude") ? Provider.claude : Provider.codex).color)
                                .frame(width: 6, height: 6)
                            Text(model).font(.system(size: 11.5, design: .monospaced)).lineLimit(1)
                            Spacer()
                            Text(Fmt.tokens(u.total))
                                .font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary).monospacedDigit()
                            Text(Fmt.percent(u.cost / totalCost * 100))
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    // MARK: Insights

    private var insights: some View {
        let items = store.insights(period)
        return Group {
            if !items.isEmpty {
                Card {
                    SectionLabel(text: "Insights")
                    ForEach(items) { i in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: i.symbol)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(i.tint)
                                .frame(width: 16)
                            Text(i.text)
                                .font(.system(size: 12))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

struct MetricOption: Hashable, Identifiable {
    var cost: Bool
    var id: Bool { cost }
}
