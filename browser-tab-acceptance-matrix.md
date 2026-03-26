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
- `/tmp/ghx-direct-acceptance.json`
- `/tmp/ghx-mirror-latest-acceptance.json`
- `/tmp/ghx-mirror-once-acceptance.json`
- `/tmp/ghx-mirror-manual-acceptance.json`
- `/tmp/ghx-profile-mode-acceptance.json`
- `/tmp/ghxgm7-ahignfzj/result.json`
- `/tmp/ghx-download-accept-cz_ycacz/result.json`
- `/tmp/ghx-popup-oauth-final-2d9a943a.json`
- `/tmp/ghx-popup-followup-keypress-7aa045da.json`
- `/tmp/ghx-browser-media-debug-managed.json`
- `/tmp/ghx-browser-media-debug-external.json`
- `/tmp/ghx-browser-teardown-stability-acceptance.json`
- `/tmp/ghx-browser-context-protocol-acceptance.json`

## Acceptance Matrix

| Area | Current state | Evidence | Known limits |
| --- | --- | --- | --- |
| Protocol version | Accepted and versioned as both `browser.tab.v1` and `browser.context.v2`. | `browser-tab-command-protocol.md`, `browser-context-command-protocol.md`, `macos/Sources/Features/Browser/BrowserCommandProtocol.swift`, `/tmp/ghx-browser-context-protocol-acceptance.json` | `browser.tab.v1` remains the compatibility vocabulary, while `browser.context.v2` is the forward-looking object-model boundary. True per-context proxy/fingerprint/storage isolation is still a later layer than the protocol versioning itself. |
| Local transports | Accepted over IPC and AppleScript with the same request/response envelope. | `browser-tab-command-protocol.md`, `macos/Sources/Features/Browser/BrowserControlIPCService.swift`, `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift` | IPC is local-only and line-delimited UTF-8 JSON. AppleScript remains a compatibility fallback. |
| IPC socket path | Accepted at `~/Library/Application Support/GhoDex/browser-control.sock`, or under the isolated app-support root when `GHODEX_BROWSER_APP_SUPPORT_ROOT` is set. | `browser-tab-command-protocol.md`, `macos/Sources/Features/Browser/BrowserPaths.swift`, `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm` | Existing external-profile source locks still matter; the app-support override relocates GhoDex-owned runtime/profile roots, not the source Chrome profile itself. |
| IPC backpressure | Accepted with per-connection response buffering capped at 1 MiB. | `browser-tab-command-protocol.md`, `macos/Sources/Features/Browser/BrowserControlIPCService.swift` | Slow readers can be disconnected; the cap is per connection, not global. |
| Browser tab discovery | Accepted: `listTabs`, `newTab`, `listPages`, `getActivePage`, `activatePage`, `listFrames`. | `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `browser-tab-command-protocol.md` | `newTab` creates a new Browser window/controller, not an internal page inside an existing Browser tab. |
| Browser context lifecycle | Accepted: `listContexts`, `getContext`, `newContext`, `activateContext`, `closeContext`, `newPageInContext`, and `closePage`, with legacy `browserTabID` aliases still resolving the same live controller objects. | `browser-context-command-protocol.md`, `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `macos/Sources/Features/Browser/BrowserCommandProtocol.swift`, `/tmp/ghx-browser-context-protocol-acceptance.json` | The current implementation maps one `BrowserTabController` to one `browserContext`, so the v2 boundary is a stable control-plane object model, not yet a fully isolated CEF runtime partition. |
| Last-window close semantics | Accepted: closing the last Browser-owned top-level window no longer terminates the whole app, while Terminal last-window closes still honor `quit-after-last-window-closed`. Browser-owned close classification includes both `BrowserTabController` and `GhoDexCEFPopupWindowController`. | `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/App/macOS/LastWindowCloseTerminationPolicy.swift`, `macos/Tests/LastWindowCloseTerminationPolicyTests.swift` | End-to-end window-close acceptance is not yet artifact-backed because the current Debug app's AppleScript dictionary is broken (`osascript` returns `-2705`), so the durable evidence for this row is product build coverage plus targeted policy regression tests. |
| Page targeting | Accepted with `browserTabID` plus optional `pageID`; page summaries expose `documentRevision`, and page-targeted commands can enforce that revision as a stale-request precondition. | `macos/Sources/Features/Browser/BrowserCommandProtocol.swift`, `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `browser-tab-command-protocol.md` | Omitting `pageID` falls back to the active page, and omitting `documentRevision` leaves the command in backward-compatible unguarded mode. |
| Frame targeting | Accepted for frame discovery plus named-frame command routing through top-level `frameName`. | `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm`, `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `browser-tab-command-protocol.md` | Only named frames are directly targetable today. Unnamed child frames remain observable in events but are not first-class external targets. |
| Debug lane status surface | Accepted: `getDebugStatus` reports `enabled`, `port`, `source`, `cefInitialized`, and `runtimeAvailable`. | `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `browser-tab-command-protocol.md` | This is diagnostics metadata only; it does not guarantee a successful external DevTools attach by itself. |
| Remote debug config | Accepted through config key `ghodex-browser-remote-debug-port`, mirrored into `BrowserCEFRemoteDebugPort`, and applied to `settings.remote_debugging_port`. | `macos/Sources/Ghostty/Ghostty.Config.swift`, `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm` | Disabled when unset or outside `1...65535`. The diagnostics lane remains off by default. |
| Remote debug default-closed isolated proof | Accepted for isolated managed and external launches after ignoring shared `BrowserCEFRemoteDebugPort` defaults whenever `GHODEX_BROWSER_APP_SUPPORT_ROOT` is set. | `/tmp/ghx-browser-media-debug-acceptance-postfix.json`, `scripts/browser_media_debug_acceptance.py`, `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm`, `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift` | The proof is intentionally for isolated acceptance sessions. A real user config can still opt back into a debug port on non-isolated runs. |
| Runtime override | Accepted through `ghodex-browser-runtime-path`, `BrowserCEFRuntimePath`, or `GHODEX_CEF_ROOT`. | `macos/Sources/Ghostty/Ghostty.Config.swift`, `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm` | The override must already exist as a directory; invalid paths are ignored. |
| Runtime round-trip evidence | Accepted and smoke-backed for repeated launches using the worktree runtime symlink path. | `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/smoke-result.json`, `cef-browser-smoke-validation.md` | The smoke harness verifies selection and initialization, not every first-run installer UI branch in-place. |
| Managed runtime download metadata | Accepted with a fixed CEF artifact URL and SHA-256 in code. | `macos/Sources/Features/Browser/BrowserPaths.swift`, `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/smoke-result.json` | Managed install still depends on the download succeeding and the archive layout remaining compatible. |
| Core browser service handlers | Accepted at the CEF client layer for file dialogs, downloads, JS dialogs, media/permission prompts, HTTP auth, certificate warnings, first-level popup/OAuth hosting, and popup-host follow-up open re-entry into GhoDex's internal Browser routing. | `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm`, `/tmp/ghx-download-accept-cz_ycacz/result.json`, `/tmp/ghx-popup-oauth-final-2d9a943a.json`, `/tmp/ghx-popup-followup-keypress-7aa045da.json`, `/tmp/ghx-browser-popup-event-acceptance.json`, `scripts/browser_js_dialog_resolution_acceptance.py`, `/tmp/ghx-browser-js-dialog-resolution-acceptance.json`, `/tmp/ghx-browser-context-protocol-acceptance-recheck.json` | Runtime prompt handlers are now externally observable and externally resolvable for dialogs, permissions, auth, and certificate warnings. A dedicated JS-dialog acceptance harness now exists, but in the current isolated acceptance environment both that harness and a fresh `browser_context_protocol_acceptance.py` recheck still block on `newContext` timing out after the socket is already live. Prompt resolution therefore remains a known blocked acceptance lane rather than a green end-to-end proof. |
| Runtime service event stream | Accepted for external observability and first-response control of download, JavaScript dialog, permission, HTTP auth, and certificate-warning lifecycles through `subscribeEvents` / `drainEvents` / `unsubscribeEvents`. The broker now forwards these CEF handler surfaces as first-class event kinds instead of leaving them visible only through internal AppKit UI. Requested prompt payloads include `requestID` so follow-up control can target the paused runtime callback, and live download payloads include `downloadID` so external callers can issue `cancelDownload` against the retained CEF download callback. | `macos/Sources/Features/Browser/BrowserCommandProtocol.swift`, `macos/Sources/Features/Browser/BrowserExternalEventBroker.swift`, `macos/Sources/Features/Browser/BrowserTabModel.swift`, `macos/Sources/Features/Browser/BrowserTabView.swift`, `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.h`, `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm`, `macos/Tests/Browser/BrowserPopupEventTests.swift` | External callers can now detect requested/resolved runtime flows, inspect stable payloads, bind typed resolve commands to `requestID`, and cancel a live in-flight download by `downloadID`. Broader download pause/resume or path redirection remains a later slice. |
| Managed profile mode | Accepted: default profile root under `~/Library/Application Support/GhoDex/CEF/Profiles/managed/<bundle-slug>`. | `macos/Sources/Features/Browser/BrowserPaths.swift`, `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm`, `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/smoke-result.json` | The concrete leaf slug depends on the app bundle identifier. |
| External profile source override | Accepted through `ghodex-browser-profile-path`, `BrowserCEFProfileSourcePath`, `BrowserCEFProfilePath`, or `GHODEX_CEF_PROFILE_PATH`. | `macos/Sources/Ghostty/Ghostty.Config.swift`, `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/Features/Browser/BrowserPaths.swift`, `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm` | The selected source must point at an existing profile directory. |
| External profile mode selection | Accepted through `ghodex-browser-profile-mode` and mirrored into `BrowserCEFProfileMode`. | `src/config/Config.zig`, `macos/Sources/Ghostty/Ghostty.Config.swift`, `macos/Sources/App/macOS/main.swift`, `macos/Sources/App/macOS/AppDelegate.swift` | Supported values are `managed`, `direct`, `mirror-latest`, `mirror-once`, and `mirror-manual`. Missing or invalid values fall back to `direct` when a source path exists, otherwise `managed`. |
| Mirrored profile sync strategy | Accepted for `mirror-latest`, `mirror-once`, and `mirror-manual` through the managed `ProfileMirrors` root. | `macos/Sources/Features/Browser/BrowserPaths.swift`, `macos/Sources/Features/SSH Connections/SSHConnectionsView.swift`, `browser-tab-cookie-lifecycle.md` | Live Chrome locks do not overwrite the last good mirror snapshot; `mirror-manual` refresh still requires the source root to be unlocked before it will copy again. |
| Mirror profile GPU/WebGL parity | Accepted for the isolated copied-`Profile 10` mirror lane after removing the forced SwiftShader-only launch flags. | `/tmp/ghx-fp-postgpu-dbqzc1yn/result.json`, `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm` | This closes the earlier "no WebGL context" fingerprint gap, but it does not by itself make GhoDex a full Chrome-equivalent browser. The same probe still reports `VIDEO_CODECS WARN h264: ""`, and popup/new-window semantics are still product-specific. |
| H.264 / AAC local playback parity | Not accepted: both isolated managed and external lanes report empty `canPlayType` results for H.264/AAC, `MediaSource.isTypeSupported(...) = false`, `navigator.mediaCapabilities.decodingInfo(...).supported = false`, and actual playback fails with `DEMUXER_ERROR_NO_SUPPORTED_STREAMS`. | `/tmp/ghx-browser-media-debug-acceptance-postfix.json`, `scripts/browser_media_debug_acceptance.py` | This is a current runtime/product blocker for claiming normal Chrome-like media parity. VP9/WebM still reports support in the same probe. |
| Copied Chrome Google/Gmail reuse | Accepted for the isolated copied-`Profile 10` mirror lane after runtime browser-signin sanitization. | `/tmp/ghxgm7-ahignfzj/result.json`, `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm` | GhoDex still is not a Chrome browser-signin client; the runtime copy intentionally strips browser-account/sync artifacts even though the copied Google web session is preserved and reusable. |
| Copied Chrome Google/Gmail reuse after GPU normalization | Accepted again for the same copied-`Profile 10` mirror lane after restoring the normal GPU/compositor stack. | `/tmp/ghx-google-postgpu-dwz3_wvy/result.json`, `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm` | The anti-fingerprint fix did not regress the core mirror-login outcome: `https://www.google.com/` still shows a signed-in hint and `https://mail.google.com/mail/u/0/#inbox` still opens `Inbox (18) - yuan80060@gmail.com - Gmail`. |
| Aggregate direct/mirror acceptance | Accepted with isolated `HOME`, dedicated source profiles, per-mode local cookie servers, and a linked host keychain view for macOS os_crypt. | `scripts/browser_profile_mirror_acceptance.py`, `/tmp/ghx-profile-mode-acceptance.json`, `/tmp/ghx-google-keychain-root-cause.json` | The aggregate harness currently proves profile/cookie semantics and control-plane health; it does not assert `UserDefaults` mirroring because the isolated launch path records empty defaults snapshots in this evidence set. |
| External profile round-trip evidence | Accepted and smoke-backed, including `user-data-dir` plus `profile-directory` wiring. | `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/app-launch.log`, `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/manual-profile19.log`, `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/smoke-result.json` | Evidence is for the `custom-profile` fixture path used by the current harness. |
| Cookie inspection API | Accepted: `getCookies` returns `url`, `domain`, `cookieHeader`, `appliedFilters`, and visible `cookies`. | `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `browser-tab-command-protocol.md` | Only page-visible `document.cookie` entries are returned, even when the command is targeted through `frameName`. |
| Cookie mutation API | Accepted: `setCookie`, `deleteCookie`, and `clearCookies` return mutation summaries including `changedCount` and `changedNames`. | `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `browser-tab-command-protocol.md` | Deletion/clear are best-effort across a small path candidate set, and the API still covers page-visible JS cookies rather than the whole Chromium store. |
| Cookie persistence backing | Accepted at the profile layer because CEF enables `persist_session_cookies = true`. | `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm` | The external command API still cannot enumerate the full persisted store directly. |
| Cookie restart proof | Accepted for both managed and external profile modes. | `/tmp/ghodex-browser-cookie-persistence-acceptance-rerun.json`, `scripts/browser_cookie_persistence_acceptance.py` | The proof currently lives in `/tmp`, so later acceptance reruns should refresh the artifact if the temp directory is cleaned. |
| Cookie scope boundary | Accepted as intentionally limited to page-visible JS cookies. | `browser-tab-command-protocol.md`, `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift` | HTTPOnly cookies and full store metadata are out of scope today. |
| JavaScript evaluation | Accepted as a control command and used internally by cookie inspection/mutation helpers. | `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `macos/Sources/Features/Browser/BrowserTabView.swift` | Requests can now combine `pageID + frameName + documentRevision`; callers still receive structured `resultJSON` instead of a typed remote object model. |
| First-class DOM command API | Accepted: `query`, `click`, `typeText`, `waitForSelector`, `getText`, `getAttributes`, `getBoundingBox`, and `getDOMSnapshot` are top-level `browser.tab.v1` commands. `click` now supports `clickMode=auto|trusted|dom`, returns trusted/native-vs-DOM metadata, and can auto-activate a background page tab before a required trusted gesture. | `macos/Sources/Features/Browser/BrowserCommandProtocol.swift`, `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `macos/Sources/Features/Browser/BrowserTabView.swift`, `macos/Sources/Features/Browser/BrowserControlScriptBuilder.swift`, `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm`, `browser-tab-command-protocol.md`, `/tmp/ghx-browser-popup-event-acceptance.json` | Trusted click is currently limited to the main frame. Unnamed child frames are still not directly targetable, and `clickMode=trusted` rejects frame-targeted requests instead of pretending a native gesture occurred there. |
| DOM batch API | Accepted: `runDOMBatch` supports `query`, `click`, `typeText`, `getText`, `getAttributes`, `getBoundingBox`, and `getDOMSnapshot`. | `macos/Sources/Features/Browser/BrowserCommandProtocol.swift`, `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `browser-tab-command-protocol.md` | `runDOMBatch` remains the batching/compatibility path now that common DOM verbs are also first-class external commands. |
| Event subscription API | Accepted: `subscribeEvents`, `drainEvents`, and `unsubscribeEvents`, including popup/new-window routing envelopes through `popupRequest` for page-tab routing, Browser-window routing, and dedicated native popup-host windows. | `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `macos/Sources/Features/Browser/BrowserExternalEventBroker.swift`, `macos/Sources/Features/Browser/BrowserTabModel.swift`, `macos/Sources/Features/Browser/BrowserTabView.swift`, `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm`, `browser-tab-command-protocol.md`, `macos/Tests/Browser/BrowserPopupEventTests.swift`, `/tmp/ghx-browser-popup-event-acceptance.json` | The broker buffers up to 256 events per subscription and reports overflow via `droppedCount`. The popup event contract is now both unit-covered and acceptance-backed through a pure IPC harness that drives trusted click gestures. |
| Browser teardown stability | Accepted for repeated isolated close/reopen cycles after moving bridge-readiness off `@Published`, deferring Browser chrome-state mirroring off structural page mutations, and driving teardown through a deterministic Browser Context harness that waits for page bridges before closing them. | `macos/Sources/Features/Browser/BrowserTabModel.swift`, `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`, `scripts/browser_teardown_stability_acceptance.py`, `/tmp/ghx-browser-teardown-stability-acceptance.json`, `/Users/leongong/Library/Logs/DiagnosticReports/GhoDex-2026-03-26-152602.ips` | The current Browser warmup path is still slow enough that `newContext` often returns a retryable `bridgeUnavailable` before the first page bridge becomes ready. The accepted teardown harness therefore uses isolated app-support state, explicit page-bridge readiness probes, and a short settle delay between close/reopen cycles to prove lifecycle stability rather than startup latency. |
| Inspection snapshot event | Accepted as a synthesized event driven by `bridgeReady` and completed navigations. | `macos/Sources/Features/Browser/BrowserExternalEventBroker.swift`, `browser-tab-command-protocol.md` | Snapshot capture is event-triggered and not a general passive DOM mirror. |
| Popup/new-tab routing | Accepted as disposition-aware routing across current-page loads, foreground/background page tabs, real popup/new-window hosting in a dedicated native popup window when Chromium requests a first-level popup browser, and popup-host follow-up `_blank` opens re-entering the original Browser controller instead of escaping the app. | `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm`, `macos/Sources/Features/Browser/BrowserTabModel.swift`, `macos/Sources/Features/Browser/BrowserTabController.swift`, `macos/Sources/Features/Browser/BrowserTabView.swift`, `/tmp/ghx-popup-oauth-final-2d9a943a.json`, `/tmp/ghx-popup-followup-keypress-7aa045da.json`, `/tmp/ghx-browser-popup-event-acceptance.json`, `CHANGELOG.md` | First-level popup/OAuth semantics are runtime-backed, and a popup-hosted follow-up user-gesture open now creates the follow-up page inside GhoDex's own Browser control plane. Remaining popup risk is no longer routing escape or missing trusted gesture support; it is broader site-specific coverage across more real-world popup trees. |

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
- direct external profile reuse when `ghodex-browser-profile-path` resolves
- mirrored profile modes that route Browser through a managed snapshot under
  `ProfileMirrors`
- isolated `GHODEX_BROWSER_APP_SUPPORT_ROOT` launches now relocating GhoDex's
  managed CEF runtime/profile/log roots consistently enough for Browser/socket
  acceptance to run without leaking back into the caller's default app-support
  tree
- copied logged-in Chrome profiles can now reuse Google/Gmail web session state
  through `mirror-latest` when the runtime-owned copy strips Chrome-only
  browser-signin artifacts but preserves cookies/storage; the current durable
  proof is `/tmp/ghxgm7-ahignfzj/result.json`
- profile mode + source-path mirroring into `UserDefaults` for the app session
- restart-based cookie reuse from the selected effective profile path, backed by
  `/tmp/ghx-profile-mode-acceptance.json` for `direct`, `mirror-once`, and
  `mirror-manual`, and reset-on-relaunch behavior for `mirror-latest`

What is not safe to assume yet:

- that invalid profile overrides trigger a hard failure; current behavior is to
  clear the mirrored defaults entry, log the invalid config-backed override, and
  keep using the effective fallback profile/runtime
- that the isolated aggregate harness proves `UserDefaults` mirroring; the
  current March 23, 2026 evidence set is focused on effective-profile and
  cookie semantics rather than defaults persistence
- that every historical Google-login failure against mirrored Chrome profiles
  means the mirror feature itself failed; `/tmp/ghx-google-keychain-root-cause.json`
  records one concrete false-negative where the isolated harness had no default
  keychain and Chromium therefore reported `Encryption is not available`
- that `mirror-manual` will refresh while another process still owns the source
  profile root; the manual refresh path intentionally errors instead of copying
  a live root

### Browser Services

Current status: materially improved, but not fully acceptance-complete.

What is safe to rely on now:

- download requests no longer die at the missing-handler boundary, and the
  current durable proof is `/tmp/ghx-download-accept-cz_ycacz/result.json`
- Browser can now provide native file-picking, JS dialog, media-permission,
  generic permission, HTTP auth, and certificate-warning UI from product-owned
  CEF client handlers instead of default silent rejection
- those runtime-handler surfaces are now externally observable through
  first-class Browser event kinds, so automation can diagnose them without
  reading private logs
- AppKit modal surfaces in the CEF bridge now marshal back onto the main thread
  instead of assuming the callback always arrives on a safe AppKit call site

What is not safe to assume yet:

- that every popup flow is fully Chrome-equivalent across arbitrary site
  patterns; first-level OAuth/opener semantics and popup-host follow-up `_blank`
  opens are now acceptance-backed, but broader real-site popup coverage is
  still smaller than Chrome's long-tail behavior
- that every new prompt surface has the same level of automated end-to-end
  acceptance coverage as download/profile/cookie flows; the external event
  surface is now unit-covered, but interactive event resolution is still future
- that site-visible media-codec or anti-bot fingerprints are fully Chrome-parity
  just because these missing service handlers now exist

### Debug

Current status: shipped as an opt-in diagnostics lane.

What is safe to rely on now:

- config key `ghodex-browser-remote-debug-port`
- defaults mirror key `BrowserCEFRemoteDebugPort`
- `getDebugStatus` as the product-facing confirmation surface
- isolated `GHODEX_BROWSER_APP_SUPPORT_ROOT` acceptance sessions now ignore any
  previously shared remote-debug port and stay at `remote_debug_port=0`, backed
  by `/tmp/ghx-browser-media-debug-managed.json` and
  `/tmp/ghx-browser-media-debug-external.json`

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
