import AppKit
import LinkrouteCore
import SwiftUI

/// Small window for editing domain rules.
@MainActor
final class RulesWindowController {
    private var window: NSWindow?

    func show(store: RuleStore, catalog: BrowserCatalog, router: Router) {
        catalog.refresh()
        let options = catalog.options.map {
            RulesView.Option(target: $0.target, title: $0.title, icon: catalog.icon($0.target.bundleID))
        }
        let view = RulesView(store: store, options: options, titleFor: catalog.title(for:)) { text in
            guard let url = URL(string: text.contains("://") ? text : "https://\(text)"),
                  let (target, reason) = router.resolve(url) else { return "" }
            return "→ \(catalog.title(for: target))  (\(reason))"
        }

        if let window {
            window.contentViewController = NSHostingController(rootView: view)
        } else {
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Linkroute Domain Rules"
            w.styleMask = [.titled, .closable, .resizable]
            w.setContentSize(NSSize(width: 640, height: 420))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct RulesView: View {
    struct Option: Identifiable {
        let target: Target
        let title: String
        let icon: NSImage?
        var id: Target { target }
    }

    @ObservedObject var store: RuleStore
    let options: [Option]
    let titleFor: (Target) -> String
    let test: (String) -> String
    @State private var testURL = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Links matching a rule always open in that browser, whatever mode you're in. "
                 + "`example.com` also covers its subdomains; add a path like `github.com/acme` to narrow it. "
                 + "The most specific rule wins.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach($store.rules) { $rule in
                    HStack {
                        Toggle("", isOn: $rule.enabled).labelsHidden()
                        TextField("example.com", text: $rule.pattern)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 180)
                        if !rule.pattern.isEmpty && !RuleMatcher.isValid(rule.pattern) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help("This pattern can't match anything. Use a host like example.com, "
                                      + "optionally with a path (github.com/acme). No ?, #, @ or spaces.")
                        }
                        Picker("", selection: $rule.target) {
                            ForEach(pickerOptions(including: rule.target)) { option in
                                Label {
                                    Text(option.title)
                                } icon: {
                                    if let icon = option.icon { Image(nsImage: icon) }
                                }
                                .tag(option.target)
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 220)
                        Button {
                            store.rules.removeAll { $0.id == rule.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete rule")
                    }
                }
                .onMove { store.rules.move(fromOffsets: $0, toOffset: $1) }
            }
            .overlay {
                if store.rules.isEmpty {
                    Text("No rules yet. Add one, or ⌥-click a link and choose “Always Open … In”.")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Add Rule") {
                    guard let first = options.first else { return }
                    store.rules.append(Rule(pattern: "", target: first.target))
                }
                .disabled(options.isEmpty)
                Spacer()
            }

            Divider()

            HStack {
                TextField("Test a link, e.g. https://app.example.com/page", text: $testURL)
                    .textFieldStyle(.roundedBorder)
                Text(testURL.isEmpty ? "" : test(testURL))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(minWidth: 220, alignment: .leading)
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 320)
    }

    /// Keep a rule's target selectable even if that browser has since been uninstalled.
    private func pickerOptions(including target: Target) -> [Option] {
        options.contains { $0.target == target }
            ? options
            : options + [Option(target: target, title: titleFor(target), icon: nil)]
    }
}
