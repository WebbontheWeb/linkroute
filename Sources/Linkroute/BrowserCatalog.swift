import AppKit
import LinkrouteCore
import UniformTypeIdentifiers

struct BrowserProfile: Hashable {
    let id: String
    let name: String
}

struct Browser {
    enum Kind {
        /// Accepts --profile-directory=<dir>; profiles listed in <dataDir>/Local State.
        case chromium(dataDir: URL)
        /// Accepts -P <name>; profiles listed in <dataDir>/profiles.ini.
        case firefox(dataDir: URL)
        /// No usable profile targeting (Safari, Arc, Orion, ...).
        case plain
    }

    let bundleID: String
    let name: String
    let appURL: URL
    let kind: Kind
    /// Every profile found on disk (may be empty if the profile list couldn't be read).
    let allProfiles: [BrowserProfile]

    /// What menus offer: empty when there are 0–1 profiles (nothing to choose between).
    var profiles: [BrowserProfile] { allProfiles.count > 1 ? allProfiles : [] }

    func profileName(_ id: String) -> String? {
        allProfiles.first { $0.id == id }?.name
    }

    /// False only when we could read the profile list and `id` isn't in it.
    func hasProfile(_ id: String) -> Bool {
        allProfiles.isEmpty || allProfiles.contains { $0.id == id }
    }
}

/// One choosable destination, as shown in menus and the rules editor.
struct TargetOption {
    let target: Target
    let title: String
    let browser: Browser
}

/// Discovers installed browsers and their profiles.
@MainActor
final class BrowserCatalog {
    private static let appSupport = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

    /// Chromium browsers whose --profile-directory flag works, keyed to their data folder.
    /// Arc is deliberately absent: it ignores the flag, so it's treated as a plain browser.
    private static let chromiumDataDirs: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.beta": "Google/Chrome Beta",
        "com.google.Chrome.dev": "Google/Chrome Dev",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.microsoft.edgemac.Beta": "Microsoft Edge Beta",
        "com.microsoft.edgemac.Dev": "Microsoft Edge Dev",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "org.chromium.Chromium": "Chromium",
    ]

    private static let firefoxDataDirs: [String: String] = [
        "org.mozilla.firefox": "Firefox",
        "org.mozilla.firefoxdeveloperedition": "Firefox",
        "org.mozilla.nightly": "Firefox",
    ]

    /// Apps that register for web links but aren't browsers (or aren't ones you'd pick).
    private static let excludedPrefixes = [
        "com.apple.dt.Xcode",
        "com.google.chrome.for.testing",  // Playwright / Puppeteer test builds
        "com.parallels.",                 // Parallels console + Windows-app shims
        "io.nwjs.",                       // NW.js-packaged apps and games
        "com.openai.codex",               // ChatGPT desktop app
        "com.openai.chat",
    ]

    /// Only real installs: skips updater staging copies, test-browser caches, etc.
    private static func isInstalledLocation(_ url: URL) -> Bool {
        let path = url.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix("/Applications/") || path.hasPrefix("/System/")
            || path.hasPrefix(home + "/Applications/")
    }

    private static func isExcluded(_ bundle: Bundle, id: String) -> Bool {
        if excludedPrefixes.contains(where: { id.hasPrefix($0) }) { return true }
        // Background/agent apps can't be a browser you'd switch to.
        if bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true { return true }
        if bundle.object(forInfoDictionaryKey: "LSUIElement") as? String == "1" { return true }
        return false
    }

    private(set) var browsers: [Browser] = []
    private var iconCache: [String: NSImage] = [:]

    func refresh() {
        let ws = NSWorkspace.shared
        let htmlHandlers = Set(ws.urlsForApplications(toOpen: .html).compactMap { Bundle(url: $0)?.bundleIdentifier })
        var seen = Set<String>()
        var found: [Browser] = []

        for appURL in ws.urlsForApplications(toOpen: URL(string: "https://example.com")!) {
            guard let bundle = Bundle(url: appURL), let id = bundle.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier,
                  Self.isInstalledLocation(appURL),
                  !Self.isExcluded(bundle, id: id),
                  htmlHandlers.contains(id),
                  seen.insert(id).inserted
            else { continue }

            var name = FileManager.default.displayName(atPath: appURL.path)
            if name.hasSuffix(".app") { name.removeLast(4) }

            let kind: Browser.Kind
            if let dir = Self.chromiumDataDirs[id] {
                kind = .chromium(dataDir: Self.appSupport.appendingPathComponent(dir))
            } else if let dir = Self.firefoxDataDirs[id] {
                kind = .firefox(dataDir: Self.appSupport.appendingPathComponent(dir))
            } else {
                kind = .plain
            }
            found.append(Browser(bundleID: id, name: name, appURL: appURL, kind: kind,
                                 allProfiles: Self.loadProfiles(kind)))
        }
        browsers = found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func loadProfiles(_ kind: Browser.Kind) -> [BrowserProfile] {
        let profiles: [BrowserProfile]
        switch kind {
        case .chromium(let dir):
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("Local State")),
                  let state = try? ChromiumLocalState(data: data) else { return [] }
            let counts = Dictionary(state.profiles.map { ($0.name, 1) }, uniquingKeysWith: +)
            // Two profiles can share a display name; tell them apart by folder.
            profiles = state.profiles.map {
                BrowserProfile(id: $0.id, name: counts[$0.name, default: 0] > 1 ? "\($0.name) (\($0.id))" : $0.name)
            }
        case .firefox(let dir):
            guard let text = try? String(contentsOf: dir.appendingPathComponent("profiles.ini"), encoding: .utf8)
            else { return [] }
            profiles = FirefoxProfiles.names(fromINI: text).map { BrowserProfile(id: $0, name: $0) }
        case .plain:
            return []
        }
        return profiles
    }

    // MARK: - Lookups

    func browser(_ bundleID: String) -> Browser? {
        browsers.first { $0.bundleID == bundleID }
    }

    func isRunning(_ bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    /// Running browsers first, each group alphabetical.
    var displayOrder: [Browser] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return browsers.filter { running.contains($0.bundleID) } + browsers.filter { !running.contains($0.bundleID) }
    }

    /// Every choosable target, flattened: each browser, then each of its profiles.
    var options: [TargetOption] {
        displayOrder.flatMap { b in
            [TargetOption(target: Target(bundleID: b.bundleID), title: b.name, browser: b)]
                + b.profiles.map {
                    TargetOption(target: Target(bundleID: b.bundleID, profileID: $0.id),
                                 title: "\(b.name) — \($0.name)", browser: b)
                }
        }
    }

    func title(for target: Target) -> String {
        guard let b = browser(target.bundleID) else { return "\(target.bundleID) (not installed)" }
        guard let pid = target.profileID else { return b.name }
        return "\(b.name) — \(b.profileName(pid) ?? pid)"
    }

    func icon(_ bundleID: String, size: CGFloat = 16) -> NSImage? {
        let key = "\(bundleID)@\(size)"
        if let cached = iconCache[key] { return cached }
        guard let b = browser(bundleID),
              let image = NSWorkspace.shared.icon(forFile: b.appURL.path).copy() as? NSImage else { return nil }
        image.size = NSSize(width: size, height: size)
        iconCache[key] = image
        return image
    }
}
