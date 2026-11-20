import Foundation

/// Reads the profile list out of a Chromium-family browser's `Local State` JSON file
/// (Chrome, Edge, Vivaldi, Brave, Chromium).
public struct ChromiumLocalState: Sendable {
    public struct Profile: Hashable, Sendable {
        public let id: String    // directory name, e.g. "Profile 1"
        public let name: String  // display name, e.g. "Work"
    }

    public let profiles: [Profile]
    public let lastUsed: String?

    public init(data: Data) throws {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let profile = root["profile"] as? [String: Any] ?? [:]
        let cache = profile["info_cache"] as? [String: Any] ?? [:]
        profiles = cache.compactMap { id, value -> Profile? in
            guard let info = value as? [String: Any] else { return nil }
            let name = (info["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
            return Profile(id: id, name: name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        lastUsed = profile["last_used"] as? String
    }
}

/// Reads profile names from Firefox's `profiles.ini`.
public enum FirefoxProfiles {
    public static func names(fromINI text: String) -> [String] {
        var names: [String] = []
        var inProfileSection = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inProfileSection = line.hasPrefix("[Profile")
            } else if inProfileSection, line.hasPrefix("Name=") {
                names.append(String(line.dropFirst("Name=".count)))
            }
        }
        return names
    }
}
