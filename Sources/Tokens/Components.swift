import SwiftUI

/// A content card: a soft glass panel with generous rounding.
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardBackground())
    }
}

/// Glass in the live app; a flat fill when rendering offscreen snapshots (glass can't be captured there).
private struct CardBackground: ViewModifier {
    static let flat = ProcessInfo.processInfo.environment["TOKENS_FLAT_CARDS"] != nil

    func body(content: Content) -> some View {
        if Self.flat {
            content.background(.white.opacity(0.08), in: .rect(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: 20))
        }
    }
}

struct SectionLabel: View {
    var text: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// A capsule segmented control rendered in Liquid Glass with a morphing selection.
struct GlassSegmented<T: Hashable & Identifiable>: View {
    var items: [T]
    @Binding var selection: T
    var title: (T) -> String
    var compact = false
    @Namespace private var ns

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(items) { item in
                    let on = item == selection
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { selection = item }
                    } label: {
                        Text(title(item))
                            .font(.system(size: compact ? 11 : 12, weight: on ? .semibold : .medium))
                            .foregroundStyle(on ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, compact ? 5 : 7)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .background {
                        if on {
                            Capsule()
                                .fill(.white.opacity(0.14))
                                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                                .matchedGeometryEffect(id: "selection", in: ns)
                        }
                    }
                }
            }
            .padding(3)
            .glassEffect(.regular, in: .capsule)
        }
    }
}

struct GlassIconButton: View {
    var symbol: String
    var spinning = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: spinning)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }
}

/// Horizontal proportion bar split by provider.
struct SplitBar: View {
    var parts: [(Color, Double)]
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let sum = max(parts.reduce(0) { $0 + $1.1 }, .leastNonzeroMagnitude)
            HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    if part.1 > 0 {
                        Capsule().fill(part.0.gradient)
                            .frame(width: max(height, (geo.size.width - CGFloat(parts.count - 1) * 2) * part.1 / sum))
                    }
                }
            }
        }
        .frame(height: height)
    }
}

/// Ring gauge used for rate-limit windows.
struct RingGauge: View {
    var percent: Double
    var label: String
    var sublabel: String
    var tint: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(.primary.opacity(0.08), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: min(max(percent / 100, 0), 1))
                    .stroke(tint.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(Fmt.percent(percent))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 58, height: 58)
            VStack(spacing: 1) {
                Text(label).font(.system(size: 11, weight: .medium))
                Text(sublabel).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct LegendDot: View {
    var color: Color
    var label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}

struct TrendBadge: View {
    var current: Double
    var previous: Double

    var body: some View {
        if previous > 0 {
            let change = (current - previous) / previous * 100
            let up = change >= 0
            HStack(spacing: 2) {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                Text(Fmt.percent(abs(change)))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(up ? Color.green : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: .capsule)
        }
    }
}
