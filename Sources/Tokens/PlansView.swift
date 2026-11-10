import Charts
import SwiftUI

struct PlansView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let claude = store.planSummary(.claude)
        let codex = store.planSummary(.codex)
        VStack(spacing: 12) {
            combined(claude, codex)
            planCard(claude) { claudeLimits }
            planCard(codex) { codexLimits }
            footnote
        }
    }

    // MARK: Combined

    private func combined(_ a: PlanSummary, _ b: PlanSummary) -> some View {
        let price = a.monthlyPrice + b.monthlyPrice
        let value = a.value30d + b.value30d
        return Card {
            SectionLabel(text: "Subscriptions · last 30 days")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(price > 0 ? Fmt.multiple(value / price) : "–")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("leverage").font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
            }
            Text("You paid \(Fmt.usd(price, cents: false))/mo and used \(Fmt.usd(value, cents: false)) worth of API tokens.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            valueBar(value: value, price: price, color: .green)
        }
    }

    /// Bar showing API value with a tick for the plan price.
    private func valueBar(value: Double, price: Double, color: Color) -> some View {
        GeometryReader { geo in
            let scale = max(value, price, 0.01)
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.07))
                Capsule().fill(color.gradient).frame(width: max(6, w * value / scale))
                if price > 0 {
                    Rectangle().fill(.primary.opacity(0.7))
                        .frame(width: 2, height: 14)
                        .offset(x: min(w - 2, w * price / scale))
                }
            }
        }
        .frame(height: 8)
        .padding(.vertical, 3)
    }

    // MARK: Per plan

    private func planCard<Limits: View>(_ s: PlanSummary, @ViewBuilder limits: () -> Limits) -> some View {
        Card {
            HStack(spacing: 8) {
                Circle().fill(s.provider.color).frame(width: 8, height: 8)
                Text(s.planName).font(.system(size: 13, weight: .semibold))
                if s.detected {
                    Text("detected")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .glassEffect(.regular.tint(s.provider.color.opacity(0.4)), in: .capsule)
                }
                Spacer()
                Text(s.monthlyPrice > 0 ? "\(Fmt.usd(s.monthlyPrice, cents: false))/mo" : "pay-as-you-go")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Fmt.usd(s.value30d, cents: false))
                    .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("API value in 30 days").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if s.monthlyPrice > 0 {
                    Text(Fmt.multiple(s.leverage))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(s.leverage >= 1 ? Color.green : Color.orange)
                }
            }
            valueBar(value: s.value30d, price: s.monthlyPrice, color: s.provider.color)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    stat("Tokens (30d)", Fmt.tokens(s.tokens30d))
                    stat("Month to date", Fmt.usd(s.valueMTD, cents: false))
                    stat("Projected", Fmt.usd(s.projectedMonth, cents: false))
                }
                if s.monthlyPrice > 0 {
                    GridRow {
                        stat("Your cost / 1M tok", s.tokens30d > 0 ? Fmt.usd(s.effectivePerMTok) : "–")
                        stat("Break-even", s.breakEvenDay.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "not yet")
                        stat("Daily value", Fmt.usd(s.value30d / 30, cents: false))
                    }
                }
            }
            .padding(.top, 2)

            limits()
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 9.5)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Limits

    @ViewBuilder private var codexLimits: some View {
        if let l = store.snapshot.codexLimits {
            Divider().opacity(0.4)
            HStack {
                Text("Usage limits").font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("as of \(Fmt.relative(Date(timeIntervalSince1970: l.timestamp)))")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            HStack {
                if let p = l.primary {
                    RingGauge(percent: p.currentPercent(), label: windowName(p.windowMinutes),
                              sublabel: p.currentPercent() == 0 && p.usedPercent > 0 ? "reset" : "resets in \(Fmt.countdown(to: p.resetsAt))",
                              tint: Provider.codex.color)
                }
                if let s = l.secondary {
                    RingGauge(percent: s.currentPercent(), label: windowName(s.windowMinutes),
                              sublabel: s.currentPercent() == 0 && s.usedPercent > 0 ? "reset" : "resets in \(Fmt.countdown(to: s.resetsAt))",
                              tint: .indigo)
                }
            }
            weeklyPeaks
        }
    }

    /// Peak weekly-limit usage per day over the last 30 days.
    @ViewBuilder private var weeklyPeaks: some View {
        let keys = store.lastDays(30)
        let points = keys.compactMap { k -> (Date, Double)? in
            guard let d = Fmt.date(k) else { return nil }
            return (d, store.snapshot.codexWeeklyPeaks[k] ?? 0)
        }
        if points.contains(where: { $0.1 > 0 }) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Weekly limit used, daily peak").font(.system(size: 10)).foregroundStyle(.secondary)
                Chart(points, id: \.0) { d, v in
                    AreaMark(x: .value("Day", d, unit: .day), y: .value("Used", v))
                        .foregroundStyle(LinearGradient(colors: [.indigo.opacity(0.45), .indigo.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Day", d, unit: .day), y: .value("Used", v))
                        .foregroundStyle(.indigo)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0, 50, 100]) { v in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(.primary.opacity(0.12))
                        AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").font(.system(size: 8.5)) }
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 54)
            }
        }
    }

    @ViewBuilder private var claudeLimits: some View {
        Divider().opacity(0.4)
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary)
            Text("Claude Code doesn't write its session and weekly limit usage to disk. Run /usage in Claude Code to see it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func windowName(_ minutes: Int) -> String {
        switch minutes {
        case 300: "5-hour window"
        case 10080: "Weekly"
        case let m where m >= 1440: "\(m / 1440)-day window"
        case let m: "\(m / 60)-hour window"
        }
    }

    private var footnote: some View {
        Text("API value = your token usage priced at public API list rates (Anthropic & OpenAI, Oct 2026), including cache reads and writes. Plans are auto-detected and can be changed in settings.")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}
