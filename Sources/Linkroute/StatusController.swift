import AppKit
import LinkrouteCore
import ServiceManagement
import UniformTypeIdentifiers

/// The menu bar item: shows where links will go and lets you switch it.
@MainActor
final class StatusController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let catalog: BrowserCatalog
    private let router: Router
    private let rules: RuleStore
    private let showRules: () -> Void

    init(catalog: BrowserCatalog, router: Router, rules: RuleStore, showRules: @escaping () -> Void) {
        self.catalog = catalog
        self.router = router
        self.rules = rules
        self.showRules = showRules
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.imagePosition = .imageLeading
        refreshButton()
    }

    /// Follow mode: a monochrome glyph. Pinned: the browser's icon plus the profile name.
    func refreshButton() {
        guard let button = item.button else { return }
        let current = router.modeTarget()
        // Only show a browser icon when that pin is actually in effect (not a fallback).
        if let (target, reason) = current, case .pinned = reason, let icon = catalog.icon(target.bundleID, size: 18) {
            button.image = icon
            let profile = target.profileID.flatMap { catalog.browser(target.bundleID)?.profileName($0) }
            button.title = profile.map { " \($0)" } ?? ""
        } else {
            let glyph = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Linkroute")
            glyph?.isTemplate = true
            button.image = glyph
            button.title = ""
        }
        button.toolTip = headline(current)
    }

    private func headline(_ current: (Target, Router.Reason)?) -> String {
        guard let (target, reason) = current else { return "No browsers found" }
        let name = catalog.title(for: target)
        switch reason {
        case .following: return "Following last-used: \(name)"
        case .pinned: return "Pinned: \(name)"
        default: return "Opening in: \(name)"
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        catalog.refresh()
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()
        let current = router.modeTarget()
        menu.addDisabled(headline(current))
        menu.addItem(.separator())

        let follow = ActionItem("Follow Last-Used Browser") { [weak self] in
            self?.router.mode = .follow
            self?.refreshButton()
        }
        follow.state = router.mode == .follow ? .on : .off
        menu.addItem(follow)

        let pinned = router.mode == .pinned ? router.pinned : nil
        let order = catalog.displayOrder
        let running = order.filter { catalog.isRunning($0.bundleID) }
        let notRunning = order.filter { !catalog.isRunning($0.bundleID) }

        if !running.isEmpty {
            menu.addItem(.separator())
            menu.addHeader("Pin to Open Browser")
            for browser in running {
                // Browser row, then its profiles indented underneath.
                menu.addItem(pinItem(Target(bundleID: browser.bundleID), title: browser.name,
                                     icon: true, pinned: pinned))
                for profile in browser.profiles {
                    let item = pinItem(Target(bundleID: browser.bundleID, profileID: profile.id),
                                       title: profile.name, icon: false, pinned: pinned)
                    item.indentationLevel = 1
                    menu.addItem(item)
                }
            }
        }

        if !notRunning.isEmpty {
            menu.addItem(.separator())
            menu.addHeader("Not Running")
            for browser in notRunning {
                let base = pinItem(Target(bundleID: browser.bundleID), title: browser.name,
                                   icon: true, pinned: pinned)
                guard !browser.profiles.isEmpty else { menu.addItem(base); continue }
                // Profiles of closed browsers live in a submenu to keep the menu short.
                let parent = NSMenuItem(title: browser.name, action: nil, keyEquivalent: "")
                parent.image = base.image
                parent.state = pinned?.bundleID == browser.bundleID ? .on : .off
                let sub = NSMenu()
                base.title = "Last-Used Profile"
                base.image = nil
                sub.addItem(base)
                sub.addItem(.separator())
                for profile in browser.profiles {
                    sub.addItem(pinItem(Target(bundleID: browser.bundleID, profileID: profile.id),
                                        title: profile.name, icon: false, pinned: pinned))
                }
                parent.submenu = sub
                menu.addItem(parent)
            }
        }

        menu.addItem(.separator())
        let ruleCount = rules.rules.filter(\.enabled).count
        menu.addItem(ActionItem(ruleCount > 0 ? "Domain Rules (\(ruleCount))…" : "Domain Rules…", key: ",") { [weak self] in
            self?.showRules()
        })
        menu.addDisabled("Hold ⌥ while clicking a link to choose")

        menu.addItem(.separator())
        if !DefaultBrowser.isLinkroute {
            menu.addItem(ActionItem("Make Linkroute the Default Browser…") {
                DefaultBrowser.makeLinkroute()
            })
        }
        let login = ActionItem("Open at Login") {
            let service = SMAppService.mainApp
            do {
                if service.status == .enabled { try service.unregister() } else { try service.register() }
            } catch {
                log.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(ActionItem("Quit Linkroute", key: "q") { NSApp.terminate(nil) })
    }

    private func pinItem(_ target: Target, title: String, icon: Bool, pinned: Target?) -> ActionItem {
        let item = ActionItem(title, image: icon ? catalog.icon(target.bundleID) : nil) { [weak self] in
            self?.router.pin(target)
            self?.refreshButton()
        }
        item.state = pinned == target ? .on : .off
        return item
    }
}

enum DefaultBrowser {
    private static let probe = URL(string: "https://example.com")!

    static var isLinkroute: Bool {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return false }
        return Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// macOS shows its own "change default browser?" confirmation for this.
    @MainActor
    static func makeLinkroute() {
        let me = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: "http") { error in
            if let error { log.error("Set default (http) failed: \(error.localizedDescription, privacy: .public)") }
            NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: "https") { error in
                if let error { log.error("Set default (https) failed: \(error.localizedDescription, privacy: .public)") }
            }
            NSWorkspace.shared.setDefaultApplication(at: me, toOpen: .html) { error in
                if let error { log.error("Set default (HTML) failed: \(error.localizedDescription, privacy: .public)") }
            }
        }
    }
}
