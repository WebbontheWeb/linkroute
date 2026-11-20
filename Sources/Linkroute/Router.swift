import AppKit
import LinkrouteCore

/// Persisted domain rules, observable by the rules editor.
@MainActor
final class RuleStore: ObservableObject {
    private static let key = "rules"

    @Published var rules: [Rule] {
        didSet { save() }
    }

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.key) else {
            rules = []
            return
        }
        do {
            rules = try JSONDecoder().decode([Rule].self, from: data)
        } catch {
            // Keep the unreadable data instead of letting the next save overwrite it.
            let backup = "\(Self.key).unreadable.\(Int(Date().timeIntervalSince1970))"
            UserDefaults.standard.set(data, forKey: backup)
            log.error("Couldn't read saved rules (backed up to \(backup, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            rules = []
        }
    }

    /// Adds a rule, replacing any existing rule with the same pattern.
    func setRule(pattern: String, target: Target) {
        let key = pattern.lowercased()
        if let i = rules.firstIndex(where: { $0.pattern.lowercased() == key }) {
            rules[i].target = target
            rules[i].enabled = true
        } else {
            rules.append(Rule(pattern: pattern, target: target))
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

/// Decides where a link goes: a matching rule, else the current mode (follow / pinned),
/// else a sensible fallback.
@MainActor
final class Router {
    enum Mode: String {
        /// Open in whichever browser was last in front.
        case follow
        /// Open in the browser/profile chosen in the menu.
        case pinned
    }

    enum Reason: CustomStringConvertible {
        case rule(String), pinned, following, fallback
        var description: String {
            switch self {
            case .rule(let p): "rule \(p)"
            case .pinned: "pinned"
            case .following: "following last-used browser"
            case .fallback: "fallback"
            }
        }
    }

    private let catalog: BrowserCatalog
    private let rules: RuleStore
    private let defaults = UserDefaults.standard

    init(catalog: BrowserCatalog, rules: RuleStore) {
        self.catalog = catalog
        self.rules = rules
    }

    var mode: Mode {
        get { Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .follow }
        set { defaults.set(newValue.rawValue, forKey: "mode") }
    }

    var pinned: Target? {
        get { defaults.data(forKey: "pinned").flatMap { try? JSONDecoder().decode(Target.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "pinned") }
    }

    /// Bundle ID of the browser most recently brought to the front.
    var lastBrowser: String? {
        get { defaults.string(forKey: "lastBrowser") }
        set { defaults.set(newValue, forKey: "lastBrowser") }
    }

    func pin(_ target: Target) {
        pinned = target
        mode = .pinned
    }

    /// Where links go when no rule matches.
    func modeTarget() -> (Target, Reason)? {
        switch mode {
        case .pinned:
            if let t = pinned, catalog.browser(t.bundleID) != nil { return (validated(t), .pinned) }
        case .follow:
            // No profile: Chromium browsers then open the link in their last-used profile window.
            if let id = lastBrowser, catalog.browser(id) != nil { return (Target(bundleID: id), .following) }
        }
        return fallback().map { ($0, .fallback) }
    }

    func resolve(_ url: URL) -> (Target, Reason)? {
        // Only consider rules whose browser is installed, so a rule for a removed browser
        // doesn't hide a broader rule that would still apply.
        let usable = rules.rules.filter { catalog.browser($0.target.bundleID) != nil }
        if let rule = RuleMatcher.bestMatch(in: usable, for: url) {
            return (validated(rule.target), .rule(rule.pattern))
        }
        return modeTarget()
    }

    /// Drops a profile that no longer exists, so the link opens at browser level instead.
    private func validated(_ target: Target) -> Target {
        guard let id = target.profileID, let browser = catalog.browser(target.bundleID),
              !browser.hasProfile(id) else { return target }
        return Target(bundleID: target.bundleID)
    }

    private func fallback() -> Target? {
        let order = catalog.displayOrder
        let pick = order.first { catalog.isRunning($0.bundleID) }
            ?? catalog.browser("com.apple.Safari")
            ?? order.first
        return pick.map { Target(bundleID: $0.bundleID) }
    }
}
