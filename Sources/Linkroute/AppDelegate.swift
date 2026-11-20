import AppKit
import LinkrouteCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let catalog = BrowserCatalog()
    private let rules = RuleStore()
    private lazy var router = Router(catalog: catalog, rules: rules)
    private let rulesWindow = RulesWindowController()
    private var status: StatusController?
    /// Bundle IDs seen activating that are known not to be browsers, so app switches stay cheap.
    private var nonBrowsers = Set<String>()

    private var dryRun: Bool { UserDefaults.standard.bool(forKey: "dryRun") }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Load browsers now: when a click launches Linkroute, AppKit delivers that link
        // *before* applicationDidFinishLaunching.
        catalog.refresh()
        NSApp.mainMenu = Self.makeMainMenu()

        // Links arrive as "get URL" Apple Events once Linkroute is the default browser.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("Found \(self.catalog.browsers.count) browsers")
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, catalog.browser(front) != nil {
            router.lastBrowser = front
        }

        status = StatusController(catalog: catalog, router: router, rules: rules) { [weak self] in
            guard let self else { return }
            rulesWindow.show(store: rules, catalog: catalog, router: router)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    // MARK: - Incoming links

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue ?? ""
        guard let url = URL(string: string), Self.isWebURL(url) else {
            // Anything else (no scheme, javascript:, file:, "--some-flag") is refused: it could be
            // misread by the browser, or passed to it as a command-line switch.
            log.error("Ignored link that isn't http(s): \(string, privacy: .private)")
            return
        }
        route([url])
    }

    /// HTML files opened with Linkroute, plus any URLs delivered via the standard open path.
    func application(_ application: NSApplication, open urls: [URL]) {
        let accepted = urls.filter { $0.isFileURL || Self.isWebURL($0) }
        if accepted.count < urls.count {
            log.error("Ignored \(urls.count - accepted.count) item(s) that weren't http(s) links or files")
        }
        if !accepted.isEmpty { route(accepted) }
    }

    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return !(url.host(percentEncoded: false) ?? "").isEmpty
    }

    private func route(_ urls: [URL]) {
        if catalog.browsers.isEmpty { catalog.refresh() }

        if NSEvent.modifierFlags.contains(.option) {
            LinkPicker.show(for: urls, catalog: catalog, rules: rules) { [weak self] target in
                guard let self else { return }
                if dryRun {
                    log.info("[dry run] picked \(self.catalog.title(for: target), privacy: .public)")
                } else {
                    Launcher.open(urls, in: target, catalog: catalog)
                }
            }
            return
        }

        for url in urls {
            guard let (target, reason) = router.resolve(url) else {
                log.error("No browser available to open a link")
                continue
            }
            let host = url.host(percentEncoded: false) ?? "file"
            let dest = "\(catalog.title(for: target)) (\(reason))"
            if dryRun {
                log.info("[dry run] \(host, privacy: .public) → \(dest, privacy: .public)")
            } else {
                log.info("\(host, privacy: .private) → \(dest, privacy: .public)")
                Launcher.open([url], in: target, catalog: catalog)
            }
        }
    }

    // MARK: - Tracking the last-used browser

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
              !nonBrowsers.contains(id) else { return }

        if catalog.browser(id) == nil {
            // Only rescan for an app that claims web links — i.e. a browser installed since launch.
            let handlesWeb = app.bundleURL.flatMap(Bundle.init(url:)).map(Self.claimsHTTPS) ?? false
            if handlesWeb { catalog.refresh() }
            guard catalog.browser(id) != nil else {
                nonBrowsers.insert(id)
                return
            }
        }
        router.lastBrowser = id
        status?.refreshButton()
    }

    private static func claimsHTTPS(_ bundle: Bundle) -> Bool {
        let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return types.contains { ($0["CFBundleURLSchemes"] as? [String] ?? []).contains { $0.lowercased() == "https" } }
    }

    // MARK: - Menu

    /// Accessory apps have no visible menu bar, but text fields still need an Edit menu
    /// for ⌘X / ⌘C / ⌘V / ⌘A / ⌘Z to work (e.g. in the Rules window).
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit Linkroute", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}
