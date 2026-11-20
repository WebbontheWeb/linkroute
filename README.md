# Linkroute

A macOS menu bar app that decides which browser — and which browser profile — opens the links you click, without touching the system default-browser setting every time.

## How it works

Linkroute registers itself as the default browser **once**. From then on every link you click in another app (Slack, Mail, Teams, Notes, …) comes to Linkroute, which immediately hands it to the right browser:

1. **Domain rules** win first. `acme.com → Edge / Work` sends every acme.com link (and its subdomains) to that profile, whatever mode you're in.
2. Otherwise, the **mode** chosen in the menu bar:
   - **Follow Last-Used Browser** (default): the link goes to whichever browser you last had in front. Chromium browsers (Chrome, Edge, Vivaldi, Brave) then open it in the profile whose window you used last, so in practice this follows your profile too.
   - **Pinned**: pick a browser, or a specific profile, from the menu; links go there until you change it.
3. **Hold ⌥ while clicking a link** to get a picker at the mouse pointer (keys 1–9 select). Its "Always Open *domain* In" submenu creates a rule on the spot.

The menu bar icon shows the state at a glance: a branch glyph while following, or the pinned browser's icon plus profile name.

## Browser support

| Browser | Browser-level | Specific profile |
| --- | --- | --- |
| Chrome, Edge, Vivaldi, Brave, Chromium | ✓ | ✓ (`--profile-directory`) |
| Firefox | ✓ | ✓ (`-P`, less tested) |
| Safari, Arc, Orion, others | ✓ | — (no external way to target a profile) |

Browsers are discovered automatically: anything in `/Applications`, `~/Applications`, or `/System` that handles web links and HTML. Background helpers, test builds (Playwright/Puppeteer), Parallels shims, and updater staging copies are filtered out.

## Build & install

Requires macOS 14+ and Xcode (Swift 5.10+).

```bash
make install   # builds, copies to ~/Applications, registers, launches
```

Then click the menu bar icon → **Make Linkroute the Default Browser…** and confirm the macOS prompt. Optionally enable **Open at Login** from the same menu.

Other targets: `make test` (unit tests), `make logs` (stream routing decisions), `make uninstall`.

To see decisions without opening anything:

```bash
defaults write com.webbontheweb.Linkroute dryRun -bool YES   # NO to turn off
make logs
```

To stop using it, choose a different default browser in System Settings → Desktop & Dock → Default web browser, turn off **Open at Login** in the menu, then `make uninstall`.

## Security notes

- Only `http`/`https` links (and HTML files opened with the app) are accepted. Anything else sent to Linkroute — `javascript:`, `file:` via the link path, or strings like `--some-flag` — is refused, and no argument starting with `-` is ever passed to a browser.
- Link hosts are logged as private in the unified log (redacted unless you enable private data); only dry-run mode logs them in the clear.
- The bundle is signed with the hardened runtime. It's ad-hoc signed and lives in `~/Applications`, which is fine for personal use; set `SIGN_IDENTITY` to a Developer ID before sharing it.

## Layout

- `Sources/LinkrouteCore` — pure logic: rule matching, Chromium `Local State` / Firefox `profiles.ini` parsing. Unit tested.
- `Sources/Linkroute` — the app: Apple Event URL handling, browser catalog, router, launcher, menu, ⌥ picker, rules window.
- `Resources/Info.plist` — declares http/https/HTML handling (required to be offered as a default browser) and `LSUIElement` (no Dock icon).
- `scripts/bundle.sh` — wraps the SwiftPM binary into `build/Linkroute.app` and ad-hoc signs it.

## Ideas not built yet

- **Source-app rules** — e.g. links clicked in Slack → a specific profile. The sender's PID is available on the incoming Apple Event.
- **Global hotkey** to cycle or pick the pinned target.
- **Recent links** menu to re-send a link that went to the wrong place.
- **Exact profile detection in follow mode** via the Accessibility API (window titles), if a browser's own "last-used profile" behavior proves unreliable.
- App icon; Developer ID signing for sharing.

## License

MIT — see [LICENSE](LICENSE).
