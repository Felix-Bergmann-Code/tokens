import Charts
import SwiftUI

struct MonthsView: View {
    @EnvironmentObject var store: Store
    @AppStorage("monthsMetric") private var showCost = true

    var body: some View {
        let months = store.months
        VStack(spacing: 12) {
            chart(months)
            heatmap
            list(months)
        }
    }

    private func chart(_ months: [Store.MonthRow]) -> some View {
        let recent = Array(months.prefix(12).reversed())
        let points = recent.flatMap { row in
            Provider.allCases.map { p in
                ChartPoint(date: row.month, provider: p, tokens: row.byProvider[p]?.total ?? 0,
                           cost: row.byProvider[p]?.cost ?? 0)
            }
        }
        return Card {
            HStack {
                SectionLabel(text: "Monthly")
                Spacer()
                GlassSegmented(items: [false, true].map(MetricOption.init), selection: Binding(
                    get: { MetricOption(cost: showCost) }, set: { showCost = $0.cost }
                ), title: { $0.cost ? "$" : "Tokens" }, compact: true)
                .frame(width: 110)
            }
            Chart(points) { pt in
                BarMark(x: .value("Month", pt.date, unit: .month),
                        y: .value("Value", showCost ? pt.cost : Double(pt.tokens)))
                    .foregroundStyle(by: .value("Provider", pt.provider.name))
                    .cornerRadius(4)
            }
            .chartForegroundStyleScale([Provider.claude.name: Provider.claude.color.gradient,
                                        Provider.codex.name: Provider.codex.color.gradient])
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(.primary.opacity(0.12))
                    AxisValueLabel {
                        if let d = v.as(Double.self) {
                            Text(showCost ? Fmt.usdCompact(d) : Fmt.tokens(Int(d))).font(.system(size: 9))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true).font(.system(size: 9))
                }
            }
            .frame(height: 140)
            HStack(spacing: 14) {
                ForEach(Provider.allCases) { LegendDot(color: $0.color, label: $0.name) }
            }
        }
    }

    private var heatmap: some View {
        let weeks = 20
        let grid = store.heatmap(weeks: weeks)
        let maxTokens = Double(grid.flatMap { $0 }.compactMap { $0?.usage.total }.max() ?? 1)
        return Card {
            SectionLabel(text: "Activity", trailing: "last \(weeks) weeks")
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<grid.count, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            cell(grid[w][d], maxTokens: maxTokens)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 4) {
                Text("Less").font(.system(size: 9)).foregroundStyle(.tertiary)
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { v in
                    RoundedRectangle(cornerRadius: 3).fill(color(v)).frame(width: 10, height: 10)
                }
                Text("More").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func cell(_ entry: (date: Date, usage: Usage)?, maxTokens: Double) -> some View {
        if let entry {
            let v = entry.usage.total > 0 ? max(0.12, sqrt(Double(entry.usage.total) / maxTokens)) : 0
            RoundedRectangle(cornerRadius: 3.5)
                .fill(color(v))
                .frame(width: 14, height: 14)
                .help("\(entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())): \(Fmt.tokens(entry.usage.total)) tokens · \(Fmt.usd(entry.usage.cost))")
        } else {
            Color.clear.frame(width: 14, height: 14)
        }
    }

    private func color(_ v: Double) -> Color {
        v == 0 ? Color.primary.opacity(0.06) : Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.2 + 0.8 * v)
    }

    private func list(_ months: [Store.MonthRow]) -> some View {
        let planCost = store.planSummary(.claude).monthlyPrice + store.planSummary(.codex).monthlyPrice
        return Card {
            SectionLabel(text: "By month", trailing: planCost > 0 ? "vs. \(Fmt.usd(planCost, cents: false))/mo in plans" : nil)
            ForEach(months) { row in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.month.formatted(.dateTime.month(.wide).year()))
                            .font(.system(size: 12.5, weight: .medium))
                        Text("\(row.activeDays) active days · \(Fmt.tokens(row.usage.total)) tokens")
                            .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Fmt.usd(row.usage.cost, cents: false))
                            .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                        if planCost > 0 {
                            Text(Fmt.multiple(row.usage.cost / planCost) + " plans")
                                .font(.system(size: 10.5, design: .rounded)).monospacedDigit()
                                .foregroundStyle(row.usage.cost >= planCost ? Color.green : Color.secondary)
                        }
                    }
                }
                if row.id != months.last?.id { Divider().opacity(0.4) }
            }
        }
    }
}
