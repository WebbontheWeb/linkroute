import Foundation

/// Matches URLs against rule patterns.
///
/// Pattern syntax (case-insensitive):
/// - `example.com` — example.com and every subdomain (www.example.com, app.example.com)
/// - `*.example.com` — same as above; the `*.` is optional
/// - `github.com/acme` — that host, limited to paths under /acme
/// - A leading `http://` or `https://`, any `:port`, and a trailing `.` on the host are ignored.
/// - Patterns containing `?`, `#`, `@`, spaces, or a `*` anywhere but the start are invalid.
///
/// When several rules match, the most specific one wins (more host labels, then longer path);
/// ties go to the rule listed first.
public enum RuleMatcher {
    public struct Pattern: Equatable, Sendable {
        public let host: String
        public let path: String
    }

    public static func parse(_ raw: String) -> Pattern? {
        var p = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for scheme in ["https://", "http://"] where p.hasPrefix(scheme) {
            p.removeFirst(scheme.count)
        }
        if p.hasPrefix("*.") { p.removeFirst(2) }

        let hostPart: Substring
        var path: String
        if let slash = p.firstIndex(of: "/") {
            hostPart = p[..<slash]
            path = String(p[slash...])
        } else {
            hostPart = p[...]
            path = ""
        }
        if p.contains(where: { "?#@* \t".contains($0) }) { return nil }
        var host = hostPart.split(separator: ":").first.map(String.init) ?? ""
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return nil }
        while path.hasSuffix("/") { path.removeLast() }
        return Pattern(host: host, path: path)
    }

    /// nil if the pattern doesn't match; otherwise a specificity score (higher = more specific).
    public static func score(_ pattern: String, url: URL) -> Int? {
        guard let p = parse(pattern),
              var urlHost = url.host(percentEncoded: false)?.lowercased()
        else { return nil }
        while urlHost.hasSuffix(".") { urlHost.removeLast() }  // "example.com." is example.com
        guard !urlHost.isEmpty else { return nil }
        guard urlHost == p.host || urlHost.hasSuffix("." + p.host) else { return nil }
        if !p.path.isEmpty {
            var urlPath = url.path(percentEncoded: false).lowercased()
            while urlPath.hasSuffix("/") { urlPath.removeLast() }
            guard urlPath == p.path || urlPath.hasPrefix(p.path + "/") else { return nil }
        }
        return p.host.split(separator: ".").count * 1000 + p.path.count
    }

    public static func isValid(_ pattern: String) -> Bool {
        parse(pattern) != nil
    }

    public static func matches(_ pattern: String, url: URL) -> Bool {
        score(pattern, url: url) != nil
    }

    public static func bestMatch(in rules: [Rule], for url: URL) -> Rule? {
        var best: (rule: Rule, score: Int)?
        for rule in rules where rule.enabled {
            guard let s = score(rule.pattern, url: url) else { continue }
            if best == nil || s > best!.score { best = (rule, s) }
        }
        return best?.rule
    }
}
