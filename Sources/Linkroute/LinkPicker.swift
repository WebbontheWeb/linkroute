import AppKit
import LinkrouteCore

/// The ⌥-click chooser: a menu at the mouse pointer listing every destination.
@MainActor
enum LinkPicker {
    static func show(for urls: [URL], catalog: BrowserCatalog, rules: RuleStore,
                     open: @escaping (Target) -> Void) {
        guard let first = urls.first else { return }
        catalog.refresh()
        let options = catalog.options
        let menu = NSMenu()
        menu.autoenablesItems = false

        let label = urls.count > 1 ? "\(urls.count) links (first: \(shorten(first)))" : shorten(first)
        menu.addDisabled("Open \(label) in…")

        for (index, option) in options.enumerated() {
            let key = index < 9 ? String(index + 1) : ""
            let item = ActionItem(option.title, key: key, image: catalog.icon(option.target.bundleID)) {
                open(option.target)
            }
            item.keyEquivalentModifierMask = []
            menu.addItem(item)
        }

        if let host = first.host(percentEncoded: false), !host.isEmpty {
            let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            menu.addItem(.separator())
            let remember = NSMenuItem(title: "Always Open \(domain) In", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for option in options {
                sub.addItem(ActionItem(option.title, image: catalog.icon(option.target.bundleID)) {
                    rules.setRule(pattern: domain, target: option.target)
                    open(option.target)
                })
            }
            remember.submenu = sub
            menu.addItem(remember)
        }

        menu.addItem(.separator())
        menu.addItem(ActionItem("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urls.map(\.absoluteString).joined(separator: "\n"), forType: .string)
        })

        // Activate so the menu gets keyboard focus (arrows, 1–9, Esc).
        NSApp.activate()
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Host + path only — never userinfo, so "https://google.com@evil.com" shows as "evil.com".
    private static func shorten(_ url: URL) -> String {
        guard let host = url.host(percentEncoded: false), !host.isEmpty else {
            return url.isFileURL ? url.lastPathComponent : "link"
        }
        let path = url.path(percentEncoded: false)
        let s = host + (path == "/" ? "" : path)
        return s.count > 50 ? String(s.prefix(47)) + "…" : s
    }
}
