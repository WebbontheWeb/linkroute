import AppKit
import LinkrouteCore
import os

let log = Logger(subsystem: "com.webbontheweb.Linkroute", category: "routing")

/// Hands URLs to a specific browser (and profile).
@MainActor
enum Launcher {
    static func open(_ urls: [URL], in target: Target, catalog: BrowserCatalog) {
        guard let browser = catalog.browser(target.bundleID) else {
            // Never fall back to NSWorkspace.open(url): Linkroute is the default browser,
            // so that would loop straight back here.
            log.error("Target \(target.bundleID, privacy: .public) not installed; dropping \(urls.count) link(s)")
            return
        }

        // Callers only pass http(s) links and absolute file paths, but never let anything that
        // looks like a command-line switch reach the browser.
        let args = urls.map { $0.isFileURL ? $0.path : $0.absoluteString }.filter { !$0.hasPrefix("-") }
        guard !args.isEmpty else { return }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        // Drop a profile that no longer exists rather than let the browser create an empty one.
        let profile = target.profileID.flatMap { browser.hasProfile($0) ? $0 : nil }

        switch (browser.kind, profile) {
        case (.chromium, let profile?):
            // A second launch with --profile-directory hands the URL to the running browser,
            // which opens it in that profile, then the new process exits.
            config.createsNewApplicationInstance = true
            config.arguments = ["--profile-directory=\(profile)"] + args
            launch(browser, config)

        case (.firefox, let profile?):
            config.createsNewApplicationInstance = true
            config.arguments = ["-P", profile] + args
            launch(browser, config)

        default:
            NSWorkspace.shared.open(urls, withApplicationAt: browser.appURL, configuration: config) { _, error in
                if let error { log.error("Open failed: \(error.localizedDescription, privacy: .public)") }
            }
        }
    }

    private static func launch(_ browser: Browser, _ config: NSWorkspace.OpenConfiguration) {
        NSWorkspace.shared.openApplication(at: browser.appURL, configuration: config) { _, error in
            if let error { log.error("Launch failed: \(error.localizedDescription, privacy: .public)") }
        }
    }
}
