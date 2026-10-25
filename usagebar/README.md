# usagebar

A native macOS 14+ menu bar app with three horizontal usage bars, grouped by provider:

- **Codex:** weekly usage in mint.
- **Claude:** weekly usage in orange and 5-hour usage in blue, under one shared heading.

The menu bar stacks all three bars vertically: Codex weekly on top, then the two Claude bars together (weekly above 5-hour). A ChatGPT icon identifies Codex; one Claude icon identifies its pair of bars. The same SVG icons appear in the popover, bundled locally from [eito.me/icons](https://eito.me/icons/).

Bars show **percent used**, not remaining. Click them for percentages, reset times, refresh, account usage pages, and Launch at Login. There is no Dock icon. Hover over the menu bar bars for a labeled summary. Unknown readings use a dash; stale readings turn gray and are labeled in the popover.

## Build and run

Requires Apple's Command Line Tools (Swift 6+), with no third-party package dependencies.

```sh
cd usagebar
./scripts/build.sh
open dist/UsageBar.app
```

To keep the app, copy `dist/UsageBar.app` to `/Applications` or `~/Applications` before enabling **Launch at Login** in its options menu. The build is locally ad-hoc signed; set `CODE_SIGN_IDENTITY` when building if you have a signing identity. Rebuilds can require Keychain approval again when using ad-hoc signing. The app is not notarized for distribution.

## Accounts

- **Codex:** install Codex CLI and sign in with `codex login` using ChatGPT. UsageBar calls the [documented app-server account interface](https://learn.chatgpt.com/docs/app-server) over local stdio, using the CLI's existing sign-in and refresh handling. It finds the CLI in Homebrew, `~/.local/bin`, the standard Codex app bundle, or inherited `PATH`. It selects the 10,080-minute window from the `codex` bucket rather than assuming a fixed window order. API-key billing does not provide subscription quota bars.
- **Claude:** sign in to the default Claude Code profile with `/login`. UsageBar reads the `Claude Code-credentials` item in macOS Keychain. Background checks never show Keychain dialogs. If access needs approval, click **Allow Keychain Access…** in the Claude section. If that item does not exist, it checks the Claude Code `.credentials.json` file. It calls Anthropic's subscription usage endpoint at `https://api.anthropic.com/api/oauth/usage`. This endpoint is not a documented public API and can change. The integration currently reads its `seven_day` and `five_hour` windows. Missing windows are shown as unavailable. API-key billing is not supported. `CLAUDE_CONFIG_DIR` selects only that profile’s credentials file; custom Keychain profiles are reported as unsupported rather than falling back to a different account.

Checks run independently for each provider at launch, after wake, every five minutes, and on manual refresh. A blocked Claude sign-in cannot prevent Codex refreshes. Claude HTTP 429 responses trigger at least a 15-minute cooldown, including for manual refresh. Failed checks retain previous values in memory and mark them stale; stale values are not replaced by zero. Values also become stale when their reset time passes or their last check is over ten minutes old.

The app never prints, saves, or rotates Claude tokens. If Claude's access token expires, open Claude Code so it can renew its own sign-in, then refresh UsageBar. No browser cookies are read. Requests go directly to Anthropic; HTTP redirects are refused. There is no app telemetry or usage history.

## Development

```sh
./scripts/verify.sh  # Full credential-free CI suite, release build, and relocated bundle/render checks
# Or only the regression tests:
./scripts/test.sh
# Live integration check: only percentages and actionable errors are printed.
# This never opens Keychain dialogs; approve access from the app popover if requested.
swift run UsageBar --check
# Visual preview with labeled sample data; makes no account requests.
open -n dist/UsageBar.app --args --demo --preview
# Render sample light/dark panels and the tray icon; also checks bundled SVG loading.
dist/UsageBar.app/Contents/MacOS/UsageBar --render-preview .build/previews
```

The Swift package can be opened in Xcode. `scripts/build.sh` produces the background `.app` bundle, including `LSUIElement` and a stable bundle identifier. Launch at Login should be configured from that bundle rather than `swift run`.

`scripts/verify.sh` also runs on macOS CI runners. The 13 regression groups use fake credentials, a mocked HTTP transport, local RPC fixtures, and injected provider closures; they never query your accounts or read Keychain.
