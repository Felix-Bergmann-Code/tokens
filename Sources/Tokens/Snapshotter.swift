import AppKit
import SwiftUI

/// `Tokens --snapshot <dir>`: renders each tab into PNGs for design review, then exits.
@MainActor
enum Snapshotter {
    static func run(dir: String) {
        let store = Store()
        Task { @MainActor in
            while !store.hasLoaded { try? await Task.sleep(for: .milliseconds(100)) }
            for tab in Tab.allCases {
                for scheme in [ColorScheme.dark, .light] {
                    let view = ZStack {
                        LinearGradient(colors: [Color(red: 0.25, green: 0.3, blue: 0.5), Color(red: 0.6, green: 0.35, blue: 0.3)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Rectangle().fill(.regularMaterial)
                        PopoverView(initialTab: tab).environmentObject(store)
                    }
                    .environment(\.colorScheme, scheme)
                    .frame(width: 392, height: 660)

                    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 392, height: 660),
                                          styleMask: [.borderless], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                    window.contentView = NSHostingView(rootView: view)
                    window.orderFrontRegardless()
                    try? await Task.sleep(for: .milliseconds(800))
                    let v = window.contentView!
                    if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                        v.cacheDisplay(in: v.bounds, to: rep)
                        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(tab.rawValue)-\(scheme == .dark ? "dark" : "light").png")
                        try? rep.representation(using: .png, properties: [:])?.write(to: url)
                    }
                    window.close()
                }
            }
            // Full-length renders of each tab's content (no scroll view), for layout review.
            for tab in Tab.allCases {
                let content = Group {
                    switch tab {
                    case .overview: OverviewView()
                    case .months: MonthsView()
                    case .plans: PlansView()
                    }
                }
                .environmentObject(store)
                .padding(14)
                .frame(width: 392)
                .background(Color(white: 0.12))
                .environment(\.colorScheme, .dark)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("full-\(tab.rawValue).png"))
                }
            }
            exit(0)
        }
    }
}
