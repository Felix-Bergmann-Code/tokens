import Foundation
import SwiftUI

enum Provider: String, Codable, CaseIterable, Identifiable {
    case claude, codex
    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    var color: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)   // clay
        case .codex: Color(red: 0.36, green: 0.56, blue: 0.98)    // cool blue
        }
    }
}

enum Source: String, Codable, CaseIterable, Identifiable {
    case claudeCLI, claudeDesktop, claudeSDK, codexDesktop, codexCLI, codexIDE
    var id: String { rawValue }

    var provider: Provider {
        switch self {
        case .claudeCLI, .claudeDesktop, .claudeSDK: .claude
        case .codexDesktop, .codexCLI, .codexIDE: .codex
        }
    }

    var label: String {
        switch self {
        case .claudeCLI: "Claude Code · Terminal"
        case .claudeDesktop: "Claude Code · Desktop"
        case .claudeSDK: "Claude Agent SDK"
        case .codexDesktop: "Codex · Desktop"
        case .codexCLI: "Codex · Terminal"
        case .codexIDE: "Codex · IDE"
        }
    }

    var symbol: String {
        switch self {
        case .claudeCLI, .codexCLI: "terminal"
        case .claudeDesktop, .codexDesktop: "macwindow"
        case .claudeSDK: "shippingbox"
        case .codexIDE: "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// Token counts for one slice of usage, plus its API-equivalent cost.
struct Usage: Codable, Equatable {
    var input: Int = 0        // uncached input
    var cacheWrite: Int = 0
    var cacheRead: Int = 0
    var output: Int = 0       // includes reasoning
    var reasoning: Int = 0
    var requests: Int = 0
    var cost: Double = 0      // USD at API list prices
    var cacheSavings: Double = 0

    var total: Int { input + cacheWrite + cacheRead + output }
    var totalInput: Int { input + cacheWrite + cacheRead }

    static func + (a: Usage, b: Usage) -> Usage {
        var r = a
        r += b
        return r
    }

    static func += (a: inout Usage, b: Usage) {
        a.input += b.input
        a.cacheWrite += b.cacheWrite
        a.cacheRead += b.cacheRead
        a.output += b.output
        a.reasoning += b.reasoning
        a.requests += b.requests
        a.cost += b.cost
        a.cacheSavings += b.cacheSavings
    }
}

/// Usage for one (local day, hour, source, model).
struct Bucket: Codable {
    var day: String   // yyyy-MM-dd, local time
    var hour: Int
    var source: Source
    var model: String
    var usage: Usage

    var key: String { "\(day)|\(hour)|\(source.rawValue)|\(model)" }
}

struct LimitWindow: Codable, Equatable {
    var usedPercent: Double
    var windowMinutes: Int
    var resetsAt: Double   // unix seconds

    /// Percent used right now, accounting for windows that have reset since the snapshot.
    func currentPercent(now: Date = .now) -> Double {
        now.timeIntervalSince1970 >= resetsAt ? 0 : usedPercent
    }
}

struct CodexLimits: Codable, Equatable {
    var timestamp: Double
    var plan: String?
    var primary: LimitWindow?
    var secondary: LimitWindow?
}

/// Everything the UI needs from one scan.
struct Snapshot {
    var buckets: [Bucket] = []
    var codexLimits: CodexLimits?
    var codexWeeklyPeaks: [String: Double] = [:]
    var claudeRateTier: String?
    var claudeSubscriptionStart: Date?
    var fileCount = 0
    var scannedAt: Date = .distantPast
}

// MARK: - Formatting

enum Fmt {
    static func tokens(_ n: Int) -> String {
        let v = Double(n)
        switch abs(v) {
        case 1e12...: return String(format: "%.2fT", v / 1e12)
        case 1e9...: return String(format: v >= 1e11 ? "%.0fB" : "%.2fB", v / 1e9)
        case 1e6...: return String(format: v >= 1e8 ? "%.0fM" : "%.1fM", v / 1e6)
        case 1e3...: return String(format: "%.0fK", v / 1e3)
        default: return "\(n)"
        }
    }

    static func usd(_ v: Double, cents: Bool? = nil) -> String {
        let showCents = cents ?? (abs(v) < 100)
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = showCents ? 2 : 0
        f.minimumFractionDigits = showCents ? 2 : 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    static func usdCompact(_ v: Double) -> String {
        if v == 0 { return "$0" }
        if v >= 10_000 { return String(format: "$%.1fk", v / 1000) }
        return usd(v, cents: v < 10)
    }

    static func multiple(_ v: Double) -> String {
        v >= 10 ? String(format: "%.0f×", v) : String(format: "%.1f×", v)
    }

    static func percent(_ v: Double) -> String { String(format: "%.0f%%", v) }

    static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(_ key: String) -> Date? { dayKey.date(from: key) }
    static func key(_ date: Date) -> String { dayKey.string(from: date) }

    static func relative(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 60 { return "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: .now)
    }

    static func countdown(to unix: Double) -> String {
        let s = max(0, unix - Date.now.timeIntervalSince1970)
        let d = Int(s) / 86400, h = (Int(s) % 86400) / 3600, m = (Int(s) % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
