import Foundation

/// Where a link should open: a browser, optionally pinned to one of its profiles.
public struct Target: Codable, Hashable, Sendable {
    public var bundleID: String
    /// Chromium: the profile directory name ("Default", "Profile 1").
    /// Firefox: the profile name from profiles.ini.
    /// nil: let the browser decide (Chromium browsers use their last-used profile).
    public var profileID: String?

    public init(bundleID: String, profileID: String? = nil) {
        self.bundleID = bundleID
        self.profileID = profileID
    }
}

/// A domain rule: links whose URL matches `pattern` always open in `target`.
public struct Rule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var pattern: String
    public var target: Target
    public var enabled: Bool

    public init(id: UUID = UUID(), pattern: String, target: Target, enabled: Bool = true) {
        self.id = id
        self.pattern = pattern
        self.target = target
        self.enabled = enabled
    }
}
