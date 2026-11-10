import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    var close: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Card {
                    SectionLabel(text: "Menu bar")
                    Picker("Show", selection: $store.menuBarStyle) {
                        ForEach(MenuBarStyle.allCases) { Text($0.name).tag($0) }
                    }
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, on in
                            do {
                                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            } catch {
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                }

                Card {
                    SectionLabel(text: "Subscriptions")
                    Picker("Claude", selection: $store.claudePlanSetting) {
                        ForEach(ClaudePlan.allCases) { p in
                            Text(p == .auto ? "Auto (\(ClaudePlan.detect(rateTier: store.snapshot.claudeRateTier)?.name ?? "none"))" : p.name).tag(p)
                        }
                    }
                    Picker("ChatGPT", selection: $store.chatgptPlanSetting) {
                        ForEach(ChatGPTPlan.allCases) { p in
                            Text(p == .auto ? "Auto (\(ChatGPTPlan.detect(planType: store.snapshot.codexLimits?.plan)?.name ?? "none"))" : p.name).tag(p)
                        }
                    }
                }

                Card {
                    SectionLabel(text: "Data")
                    VStack(alignment: .leading, spacing: 4) {
                        path("~/.claude/projects", "Claude Code (terminal, desktop, SDK)")
                        path("~/.codex/sessions", "Codex (desktop, terminal, IDE)")
                    }
                    Text("Everything is read locally. Nothing leaves your Mac.")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    HStack {
                        Button("Rebuild index") { store.refresh(rebuild: true); close() }
                            .buttonStyle(.glass)
                        Spacer()
                        Button("Quit Tokens") { NSApp.terminate(nil) }
                            .buttonStyle(.glass)
                    }
                }
            }
        }
        .scrollIndicators(.never)
        .font(.system(size: 12))
    }

    private func path(_ p: String, _ note: String) -> some View {
        HStack {
            Text(p).font(.system(size: 11, design: .monospaced))
            Spacer()
            Text(note).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }
}
