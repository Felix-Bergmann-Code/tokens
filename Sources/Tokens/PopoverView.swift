import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case overview, months, plans
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .months: "Months"
        case .plans: "Plans"
        }
    }
}

struct PopoverView: View {
    @EnvironmentObject var store: Store
    @State private var tab: Tab
    @State private var showSettings = false

    init(initialTab: Tab = .overview) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            if showSettings {
                SettingsView(close: { withAnimation(.snappy) { showSettings = false } })
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                GlassSegmented(items: Tab.allCases, selection: $tab, title: \.title)
                if !store.hasLoaded {
                    loading
                } else {
                    ScrollView {
                        Group {
                            switch tab {
                            case .overview: OverviewView()
                            case .months: MonthsView()
                            case .plans: PlansView()
                            }
                        }
                        .padding(.bottom, 6)
                    }
                    .scrollIndicators(.never)
                }
            }
        }
        .padding(14)
        .frame(width: 392, height: 660, alignment: .top)
        .onAppear { if store.hasLoaded { store.refresh() } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [Provider.claude.color, Provider.codex.color],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 32, height: 32)
                .glassEffect(.regular, in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text("Tokens").font(.system(size: 14, weight: .semibold))
                TimelineView(.periodic(from: .now, by: 15)) { _ in
                    HStack(spacing: 5) {
                        if store.isWatching && store.hasLoaded { LivePulse(tick: store.liveTick) }
                        Text(statusLine)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    GlassIconButton(symbol: "arrow.clockwise", spinning: store.isScanning && !store.hasLoaded) { store.refresh() }
                    GlassIconButton(symbol: showSettings ? "xmark" : "slider.horizontal.3") {
                        withAnimation(.snappy) { showSettings.toggle() }
                    }
                }
            }
        }
    }

    private var statusLine: String {
        if store.isScanning && !store.hasLoaded {
            return "Reading session logs… \(Int(store.progress * 100))%"
        }
        let updated = Fmt.relative(store.snapshot.scannedAt)
        return store.isWatching
            ? "Live · \(store.snapshot.fileCount) sessions · \(updated)"
            : "\(store.snapshot.fileCount) sessions · updated \(updated)"
    }

    private var loading: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView(value: store.progress)
                .progressViewStyle(.linear)
                .frame(width: 180)
            Text("Indexing your Claude Code & Codex history.\nThis only takes long the first time.")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Small green dot that flashes whenever new agent activity arrives.
struct LivePulse: View {
    var tick: Int
    @State private var flash = false

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 6, height: 6)
            .shadow(color: .green.opacity(flash ? 0.9 : 0.3), radius: flash ? 5 : 1.5)
            .scaleEffect(flash ? 1.5 : 1)
            .onChange(of: tick) {
                withAnimation(.easeOut(duration: 0.15)) { flash = true }
                withAnimation(.easeIn(duration: 0.8).delay(0.15)) { flash = false }
            }
    }
}
