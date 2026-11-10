import Foundation

/// API list prices in USD per million tokens.
struct Price {
    var input: Double
    var cachedInput: Double
    var output: Double
    /// Anthropic cache writes: 5-minute TTL at 1.25× input, 1-hour TTL at 2× input.
    var cacheWrite5m: Double { input * 1.25 }
    var cacheWrite1h: Double { input * 2 }
}

enum Pricing {
    // Ordered most-specific first; matched by prefix on the normalized model id.
    // Claude: Anthropic first-party rates (Oct 2026).
    private static let claude: [(String, Price)] = [
        ("claude-fable-5-1", Price(input: 10, cachedInput: 0.25, output: 50)),
        ("claude-mythos", Price(input: 10, cachedInput: 1.0, output: 50)),
        ("claude-fable", Price(input: 10, cachedInput: 1.0, output: 50)),
        ("claude-opus-5-5", Price(input: 4, cachedInput: 0.20, output: 20)),
        ("claude-opus-5", Price(input: 5, cachedInput: 0.50, output: 25)),
        ("claude-opus-4-8", Price(input: 5, cachedInput: 0.50, output: 25)),
        ("claude-opus-4-7", Price(input: 5, cachedInput: 0.50, output: 25)),
        ("claude-opus-4-6", Price(input: 5, cachedInput: 0.50, output: 25)),
        ("claude-opus-4-5", Price(input: 5, cachedInput: 0.50, output: 25)),
        ("claude-opus-4", Price(input: 15, cachedInput: 1.50, output: 75)),
        ("claude-sonnet-5", Price(input: 2, cachedInput: 0.20, output: 10)),
        ("claude-sonnet-4", Price(input: 3, cachedInput: 0.30, output: 15)),
        ("claude-3-7-sonnet", Price(input: 3, cachedInput: 0.30, output: 15)),
        ("claude-haiku-5", Price(input: 0.10, cachedInput: 0.01, output: 0.50)),
        ("claude-haiku-4", Price(input: 1, cachedInput: 0.10, output: 5)),
        ("claude-3-5-haiku", Price(input: 0.80, cachedInput: 0.08, output: 4)),
    ]
    private static let claudeFallback = Price(input: 4, cachedInput: 0.20, output: 20)

    // OpenAI standard-tier rates (Oct 2026).
    private static let openai: [(String, Price)] = [
        ("gpt-6.1-sol", Price(input: 2, cachedInput: 0.10, output: 10)),
        ("gpt-6-astra", Price(input: 10, cachedInput: 1.0, output: 50)),
        ("gpt-6-luna", Price(input: 0.10, cachedInput: 0.01, output: 0.50)),
        ("gpt-6-sol", Price(input: 2, cachedInput: 0.20, output: 10)),
        ("gpt-5.6-sol", Price(input: 4, cachedInput: 0.40, output: 20)),
        ("gpt-5.6-terra", Price(input: 2, cachedInput: 0.20, output: 12)),
        ("gpt-5.6-luna", Price(input: 0.20, cachedInput: 0.02, output: 1.20)),
        ("gpt-5.5", Price(input: 5, cachedInput: 0.50, output: 30)),
        ("gpt-5.4-nano", Price(input: 0.20, cachedInput: 0.02, output: 1.25)),
        ("gpt-5.4-mini", Price(input: 0.75, cachedInput: 0.075, output: 4.50)),
        ("gpt-5.4", Price(input: 2.50, cachedInput: 0.25, output: 15)),
        ("gpt-5.3", Price(input: 1.75, cachedInput: 0.175, output: 14)),
        ("gpt-5.2", Price(input: 1.75, cachedInput: 0.175, output: 14)),
        ("gpt-5.1-codex-mini", Price(input: 0.25, cachedInput: 0.025, output: 2)),
        ("gpt-5-mini", Price(input: 0.25, cachedInput: 0.025, output: 2)),
        ("gpt-5-nano", Price(input: 0.05, cachedInput: 0.005, output: 0.40)),
        ("gpt-5.1", Price(input: 1.25, cachedInput: 0.125, output: 10)),
        ("gpt-5", Price(input: 1.25, cachedInput: 0.125, output: 10)),
        // Codex's internal reviewer; no public price, priced like a mini model.
        ("codex-auto-review", Price(input: 0.75, cachedInput: 0.075, output: 4.50)),
    ]
    private static let openaiFallback = Price(input: 5, cachedInput: 0.50, output: 30)

    static func price(for model: String, provider: Provider) -> Price {
        let m = model.lowercased()
        switch provider {
        case .claude:
            return claude.first { m.hasPrefix($0.0) }?.1 ?? claudeFallback
        case .codex:
            return openai.first { m.hasPrefix($0.0) }?.1 ?? openaiFallback
        }
    }
}

// MARK: - Subscriptions

enum ClaudePlan: String, CaseIterable, Identifiable {
    case auto, none, pro, max5x, max20x, team, teamPremium
    var id: String { rawValue }

    var name: String {
        switch self {
        case .auto: "Auto-detect"
        case .none: "No subscription (API)"
        case .pro: "Claude Pro"
        case .max5x: "Claude Max 5×"
        case .max20x: "Claude Max 20×"
        case .team: "Claude Team"
        case .teamPremium: "Claude Team Premium"
        }
    }

    var monthlyPrice: Double {
        switch self {
        case .auto, .none: 0
        case .pro: 20
        case .max5x: 100
        case .max20x: 200
        case .team: 30
        case .teamPremium: 150
        }
    }

    static func detect(rateTier: String?) -> ClaudePlan? {
        guard let t = rateTier?.lowercased() else { return nil }
        if t.contains("max_20x") { return .max20x }
        if t.contains("max_5x") || t.contains("max") { return .max5x }
        if t.contains("pro") { return .pro }
        return nil
    }
}

enum ChatGPTPlan: String, CaseIterable, Identifiable {
    case auto, none, go, plus, pro, business, enterprise
    var id: String { rawValue }

    var name: String {
        switch self {
        case .auto: "Auto-detect"
        case .none: "No subscription (API)"
        case .go: "ChatGPT Go"
        case .plus: "ChatGPT Plus"
        case .pro: "ChatGPT Pro"
        case .business: "ChatGPT Business"
        case .enterprise: "ChatGPT Enterprise"
        }
    }

    var monthlyPrice: Double {
        switch self {
        case .auto, .none: 0
        case .go: 8
        case .plus: 20
        case .pro: 200
        case .business: 30
        case .enterprise: 60
        }
    }

    static func detect(planType: String?) -> ChatGPTPlan? {
        switch planType?.lowercased() {
        case "plus": .plus
        case "pro": .pro
        case "go": .go
        case "team", "business": .business
        case "enterprise", "edu": .enterprise
        case "free": ChatGPTPlan.none
        default: nil
        }
    }
}
