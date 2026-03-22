# Browser Tab Acceptance Matrix

## Purpose

This matrix records what the current Browser tab implementation already ships,
what evidence exists in this worktree or adjacent workspace artifacts, and what
scope remains intentionally limited.

This is a status document, not a future plan. It is meant to be durable enough
for later agents to answer "what is actually landed now?" without re-reading
all browser code.

For cookie lifecycle and semantics, see `browser-tab-cookie-lifecycle.md`.

## Evidence Sources Used Here

Primary code sources:

- `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`
- `macos/Sources/Features/Browser/BrowserCommandProtocol.swift`
- `macos/Sources/Features/Browser/BrowserControlIPCService.swift`
- `macos/Sources/Features/Browser/BrowserExternalEventBroker.swift`
- `macos/Sources/Features/Browser/BrowserPaths.swift`
- `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm`
- `browser-tab-command-protocol.md`
- `cef-browser-smoke-validation.md`

Stable artifact paths already present in the workspace:

- `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/smoke-result.json`
- `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/defaults-snapshot.plist`
- `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/app-launch.log`
- `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/manual-profile19.log`
- `/tmp/ghodex-browser-cookie-persistence-acceptance-rerun.json`

## Acceptance Matrix

| Area | Current state | Evidence | Known limits |
| --- | --- | --- | --- |
| Protocol version | Accepted and versioned as `browser.tab.v1`. | `browser-tab-command-protocol.md`, `macos/Sources/Features/Browser/BrowserCommandProtocol.swift` | New fields and event kinds should be treated as forward-compatible, but only `browser.tab.v1` is accepted today. |
| Local transports | Accepted over IPC and AppleScript with the same request/response envelope. | `browser-tab-command-protocol.md`, `macos/Sources/Features/Browser/BrowserControlIPCService.swift`, `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift` | IPC is local-only and line-delimited UTF-8 JSON. AppleScript remains a compatibility fallback. |
| IPC socket path | Accepted at `~/Library/Application Support/GhoDex/browser-control.sock`, or under the isolated app-support root when `GHODEX_BROWSER_APP_SUPPORT_ROOT` is set. | `browser-tab-command-protocol.md`, `macos/Sources/Features/Browser/BrowserPaths.swift` | The active CEF runtime/profile path is not automatically relocated by the app-support override alone. |
| IPC backpressure | Accepted with per-connection response buffering capped at 1 MiB. | `browser-tab-command-protocol.md`, `macos/Sources/Features/Browser/BrowserControlIPCService.swift` | Slow readers can be disconnected; the cap is per connection, not global. |
| Browser tab discovery | Accepted: `listTabs`, `newTab`, `listPages`, `getActivePage`, `activatePage`, `listFrames`. | `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `browser-tab-command-protocol.md` | `newTab` creates a new Browser window/controller, not an internal page inside an existing Browser tab. |
| Page targeting | Accepted with `browserTabID` plus optional `pageID`; page summaries expose `documentRevision`, and page-targeted commands can enforce that revision as a stale-request precondition. | `macos/Sources/Features/Browser/BrowserCommandProtocol.swift`, `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `browser-tab-command-protocol.md` | Omitting `pageID` falls back to the active page, and omitting `documentRevision` leaves the command in backward-compatible unguarded mode. |
| Frame targeting | Accepted for frame discovery plus named-frame command routing through top-level `frameName`. | `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm`, `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `browser-tab-command-protocol.md` | Only named frames are directly targetable today. Unnamed child frames remain observable in events but are not first-class external targets. |
| Debug lane status surface | Accepted: `getDebugStatus` reports `enabled`, `port`, `source`, `cefInitialized`, and `runtimeAvailable`. | `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `browser-tab-command-protocol.md` | This is diagnostics metadata only; it does not guarantee a successful external DevTools attach by itself. |
| Remote debug config | Accepted through config key `ghodex-browser-remote-debug-port`, mirrored into `BrowserCEFRemoteDebugPort`, and applied to `settings.remote_debugging_port`. | `macos/Sources/Ghostty/Ghostty.Config.swift`, `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm` | Disabled when unset or outside `1...65535`. The diagnostics lane remains off by default. |
| Runtime override | Accepted through `ghodex-browser-runtime-path`, `BrowserCEFRuntimePath`, or `GHODEX_CEF_ROOT`. | `macos/Sources/Ghostty/Ghostty.Config.swift`, `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm` | The override must already exist as a directory; invalid paths are ignored. |
| Runtime round-trip evidence | Accepted and smoke-backed for repeated launches using the worktree runtime symlink path. | `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/smoke-result.json`, `cef-browser-smoke-validation.md` | The smoke harness verifies selection and initialization, not every first-run installer UI branch in-place. |
| Managed runtime download metadata | Accepted with a fixed CEF artifact URL and SHA-256 in code. | `macos/Sources/Features/Browser/BrowserPaths.swift`, `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/smoke-result.json` | Managed install still depends on the download succeeding and the archive layout remaining compatible. |
| Managed profile mode | Accepted: default profile root under `~/Library/Application Support/GhoDex/CEF/Profiles/managed/<bundle-slug>`. | `macos/Sources/Features/Browser/BrowserPaths.swift`, `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm`, `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/smoke-result.json` | The concrete leaf slug depends on the app bundle identifier. |
| External profile override | Accepted through `ghodex-browser-profile-path`, `BrowserCEFProfilePath`, or `GHODEX_CEF_PROFILE_PATH`. | `macos/Sources/Ghostty/Ghostty.Config.swift`, `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm` | The override must point at an existing directory. |
| External profile round-trip evidence | Accepted and smoke-backed, including `user-data-dir` plus `profile-directory` wiring. | `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/app-launch.log`, `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/manual-profile19.log`, `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/smoke-result.json` | Evidence is for the `custom-profile` fixture path used by the current harness. |
| Cookie inspection API | Accepted: `getCookies` returns `url`, `domain`, `cookieHeader`, `appliedFilters`, and visible `cookies`. | `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `browser-tab-command-protocol.md` | Only page-visible `document.cookie` entries are returned, even when the command is targeted through `frameName`. |
| Cookie mutation API | Accepted: `setCookie`, `deleteCookie`, and `clearCookies` return mutation summaries including `changedCount` and `changedNames`. | `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `browser-tab-command-protocol.md` | Deletion/clear are best-effort across a small path candidate set, and the API still covers page-visible JS cookies rather than the whole Chromium store. |
| Cookie persistence backing | Accepted at the profile layer because CEF enables `persist_session_cookies = true`. | `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm` | The external command API still cannot enumerate the full persisted store directly. |
| Cookie restart proof | Accepted for both managed and external profile modes. | `/tmp/ghodex-browser-cookie-persistence-acceptance-rerun.json`, `scripts/browser_cookie_persistence_acceptance.py` | The proof currently lives in `/tmp`, so later acceptance reruns should refresh the artifact if the temp directory is cleaned. |
| Cookie scope boundary | Accepted as intentionally limited to page-visible JS cookies. | `browser-tab-command-protocol.md`, `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift` | HTTPOnly cookies and full store metadata are out of scope today. |
| JavaScript evaluation | Accepted as a control command and used internally by cookie inspection/mutation helpers. | `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `macos/Sources/Features/Browser/BrowserTabView.swift` | Requests can now combine `pageID + frameName + documentRevision`; callers still receive structured `resultJSON` instead of a typed remote object model. |
| First-class DOM command API | Accepted: `query`, `click`, `typeText`, `waitForSelector`, `getText`, `getAttributes`, `getBoundingBox`, and `getDOMSnapshot` are top-level `browser.tab.v1` commands. | `macos/Sources/Features/Browser/BrowserCommandProtocol.swift`, `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `browser-tab-command-protocol.md` | Payloads remain string-valued and unnamed child frames are still not directly targetable. |
| DOM batch API | Accepted: `runDOMBatch` supports `query`, `click`, `typeText`, `getText`, `getAttributes`, `getBoundingBox`, and `getDOMSnapshot`. | `macos/Sources/Features/Browser/BrowserCommandProtocol.swift`, `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `browser-tab-command-protocol.md` | `runDOMBatch` remains the batching/compatibility path now that common DOM verbs are also first-class external commands. |
| Event subscription API | Accepted: `subscribeEvents`, `drainEvents`, and `unsubscribeEvents`. | `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `macos/Sources/Features/Browser/BrowserExternalEventBroker.swift`, `browser-tab-command-protocol.md` | The broker buffers up to 256 events per subscription and reports overflow via `droppedCount`. |
| Inspection snapshot event | Accepted as a synthesized event driven by `bridgeReady` and completed navigations. | `macos/Sources/Features/Browser/BrowserExternalEventBroker.swift`, `browser-tab-command-protocol.md` | Snapshot capture is event-triggered and not a general passive DOM mirror. |
| Popup/new-tab routing | Accepted and smoke-backed for Browser page-tab grouping behavior. | `cef-browser-smoke-validation.md`, `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/smoke-result.json` | The artifact proves page-tab routing, not every Browser window-management edge case. |

## Practical Readout

### Cookie

Current status: shipped, but intentionally scoped.

What is safe to rely on now:

- page-local cookie inspection and mutation through `browser.tab.v1`
- persistent backing through the selected CEF profile
- deterministic targeting when callers provide both `browserTabID` and `pageID`

What is not safe to assume yet:

- access to HTTPOnly cookies
- full Chromium cookie store enumeration
- metadata-rich cookie inspection beyond what `document.cookie` exposes

### Profile

Current status: shipped and smoke-backed.

What is safe to rely on now:

- managed profile fallback when no override is set
- external profile reuse when `ghodex-browser-profile-path` resolves
- profile override mirroring into `UserDefaults` for the app session

What is not safe to assume yet:

- that an isolated app-support root alone relocates the active CEF cookie store
- that invalid profile overrides trigger a hard failure; current behavior is to
  clear the mirrored defaults entry, log the invalid config-backed override, and
  keep using the effective fallback profile/runtime

### Debug

Current status: shipped as an opt-in diagnostics lane.

What is safe to rely on now:

- config key `ghodex-browser-remote-debug-port`
- defaults mirror key `BrowserCEFRemoteDebugPort`
- `getDebugStatus` as the product-facing confirmation surface

What is not safe to assume yet:

- that remote debugging is part of the main product automation contract
- that a debug port is available without explicit config

### API

Current status: shipped and durable enough for local clients.

What is safe to rely on now:

- `browser.tab.v1` request/response envelopes
- IPC plus AppleScript adapter parity at the command layer
- explicit structured errors with retryability flags

What is not safe to assume yet:

- that undocumented commands or payload keys are supported
- that internal CEF or Swift types are part of the stable external contract

## Related Documents

- `browser-tab-cookie-lifecycle.md`
- `browser-tab-command-protocol.md`
- `cef-browser-smoke-validation.md`
