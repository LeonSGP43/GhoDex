# Browser Tab Cookie Lifecycle

## Purpose

This note describes how the current Browser tab implementation stores cookie-backed
state, which API surfaces can observe or mutate cookies, and where the current
scope intentionally stops.

This document reflects the implementation currently wired through:

- `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`
- `macos/Sources/Features/Browser/BrowserCommandProtocol.swift`
- `macos/Sources/Features/Browser/BrowserPaths.swift`
- `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm`
- `browser-tab-command-protocol.md`

For acceptance status and evidence paths, see `browser-tab-acceptance-matrix.md`.

## Current Storage Model

The current Browser tab stack has two separate layers that matter for cookies.

### 1. Browser profile selection

CEF persistence is rooted either in a managed profile or in an external
Chromium-style profile override.

Managed profile mode:

- default root: `~/Library/Application Support/GhoDex/CEF/Profiles/managed/<bundle-slug>`
- the slug comes from the app bundle identifier when available
- the current debug-build evidence path is
  `/Users/leongong/Library/Application Support/GhoDex/CEF/Profiles/managed/com.leongong.ghodex.debug`
- CEF enables `persist_session_cookies = true`, so session cookies are intended
  to survive app restarts within the selected profile root

External profile mode:

- env override: `GHODEX_CEF_PROFILE_PATH`
- mirrored defaults key: `BrowserCEFProfilePath`
- config key: `ghodex-browser-profile-path`
- when present, GhoDex treats the override as a concrete Chromium profile
  directory and passes its parent as `user-data-dir` plus the leaf name as
  `profile-directory`

Concrete evidence from the current workspace:

- profile round-trip artifact:
  `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/smoke-result.json`
- defaults snapshot:
  `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/defaults-snapshot.plist`
- live startup log with external profile wiring:
  `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/app-launch.log`
- restart-based cookie persistence proof for both managed and external modes:
  `/tmp/ghodex-browser-cookie-persistence-acceptance-rerun.json`

### 2. Cookie control surface

The current external cookie commands do not talk directly to the CEF cookie
manager. They operate through page JavaScript and the active page's
`document.cookie` view.

That means the command layer sees only cookies that are visible to page JS on
that page at that moment.

## Effective Cookie Lifecycle

### Managed profile lifecycle

1. Browser startup chooses the managed profile root when no external profile
   override is active.
2. Chromium persists page cookies into that managed profile.
3. A later GhoDex session that resolves to the same managed profile root sees
   the same persisted cookie jar.
4. The external command API can only inspect the subset currently exposed by the
   active page's `document.cookie` string.

### External profile lifecycle

1. Browser startup resolves `ghodex-browser-profile-path`, `BrowserCEFProfilePath`,
   or `GHODEX_CEF_PROFILE_PATH`.
2. CEF launches against that existing Chromium-style user-data directory.
3. Browser tabs reuse the cookie jar that already exists inside that profile.
4. External cookie commands still only operate on `document.cookie`, even though
   the underlying profile may also contain HTTPOnly or otherwise hidden cookies.

### Invalid override behavior

Config-driven runtime/profile overrides now go through existing-directory
validation before they are mirrored into Browser-related `UserDefaults`.

Current behavior:

- valid existing directories are mirrored and become effective candidates
- explicit empty config values still clear the override
- invalid config-backed overrides are removed from the mirrored defaults entry
  and logged so the fallback is observable
- the Browser runtime then continues with the remaining effective source,
  usually the managed defaults

### Isolated test root notes

`BrowserPaths` also supports `GHODEX_BROWSER_APP_SUPPORT_ROOT`, which moves the
Browser tab app-support root used for paths like the local IPC socket and the
managed runtime location chosen by `BrowserPaths`.

However, the current CEF bridge itself reads runtime/profile settings from:

- `GHODEX_CEF_ROOT`
- `GHODEX_CEF_PROFILE_PATH`
- `BrowserCEFRuntimePath`
- `BrowserCEFProfilePath`
- `BrowserCEFRemoteDebugPort`

So an isolated app-support root by itself does not redefine active cookie
storage unless the runtime/profile selection is also routed through those env or
`UserDefaults` inputs.

## API Semantics

The stable external protocol version is `browser.tab.v1`.

Cookie-related command names:

- `getCookies`
- `setCookie`
- `deleteCookie`
- `clearCookies`

Other related commands often used beside cookie flows:

- `listTabs`
- `newTab`
- `listPages`
- `getActivePage`
- `activatePage`
- `loadURL`
- `evaluateJavaScript`
- `runDOMBatch`
- `getDebugStatus`

Transport surfaces currently using the same request/response envelope:

- IPC socket at `~/Library/Application Support/GhoDex/browser-control.sock`
- AppleScript command `run browser command protocol <requestJSON>`

## Request Targeting Rules

For cookie commands, callers should treat `browserTabID` as required and
`pageID` as optional but strongly preferred.

Current targeting behavior:

- `browserTabID` must resolve to a live Browser tab
- when `pageID` is omitted, the active page inside that Browser tab is used
- when `pageID` is present, it must be a UUID from `listPages`
- results are scoped to the selected page's current `document.cookie` view

## `getCookies`

Accepted payload keys:

- `name`
- `domain`
- `url`

Semantics:

- all payload keys are optional filters
- `name` matches the visible cookie name exactly
- `domain` is compared against the current page hostname by exact match or
  suffix match
- `url` must equal the current page URL exactly
- the result includes the current `url`, `domain`, raw `cookieHeader`, the
  `appliedFilters`, and the filtered `cookies` array

Important limit:

- this command inspects `document.cookie`, not the full Chromium cookie store

## `setCookie`

Accepted payload keys:

- `name`
- `value`
- `domain`
- `path`
- `expires`
- `maxAge`
- `sameSite`
- `secure`

Normalization and validation:

- `name` is required
- `value` defaults to the empty string when omitted
- `path` defaults to `/`
- `maxAge` must parse as an integer string
- `sameSite` must be `Lax`, `Strict`, or `None`
- `secure` must be `true` or `false` when provided

Mutation behavior:

- the command writes through `document.cookie = ...`
- cookie values are written with `encodeURIComponent(...)`
- the response reports the normalized `appliedPayload`, `changedCount`,
  `changedNames`, updated `cookieHeader`, and the visible `cookies` after the
  write

## `deleteCookie`

Accepted payload keys:

- `name`
- `domain`
- `path`

Normalization and validation:

- `name` is required
- only `name`, `domain`, and `path` survive normalization

Mutation behavior:

- the command expires the named cookie with `Expires=Thu, 01 Jan 1970 00:00:00 GMT`
  and `Max-Age=0`
- when `path` is omitted, it tries a best-effort set of path candidates built
  from the current page context:
  - explicit payload path when present
  - `/`
  - current directory
  - current full pathname

## `clearCookies`

Accepted payload keys:

- `domain`
- `path`

Normalization:

- all fields are optional
- only `domain` and `path` survive normalization

Mutation behavior:

- the command reads the current visible cookie list from `document.cookie`
- it expires each visible cookie name across the same best-effort path
  candidates used by `deleteCookie`
- `changedNames` is based on the cookie names visible before the clear attempt

## Known Scope Limits

These limits are intentional in the current implementation and should be treated
as part of the current contract until the code changes.

### Visible-cookie scope only

The external cookie API currently operates only on page-visible cookies.

Out of scope today:

- HTTPOnly cookies
- direct enumeration of the full Chromium cookie store
- cookie metadata such as creation time, host-only status, priority, partition
  key, or source scheme
- cross-page or global-cookie queries without selecting a concrete Browser page

The extracted full CEF headers in
`/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/extracted-runtime/cef_binary_145.0.28+g51162e8+chromium-145.0.7632.160_macosarm64_minimal/include/cef_cookie.h`
show that CEF has a richer cookie manager API, but the current Browser control
surface has not adopted it yet.

### Best-effort deletion semantics

`deleteCookie` and `clearCookies` are best-effort helpers, not full store-wide
cookie deletion primitives.

That means:

- deletion is limited to what the page can currently see
- path matching is heuristic when the caller omits `path`
- a successful JSON response means the Browser tab executed the mutation logic,
  not that every store-level cookie variant was removed

### Page-local semantics

Cookie commands are page-local because they are executed in the context of one
Browser page.

Practical consequences:

- results can differ across pages in the same Browser tab if they are on
  different origins
- callers should use `listPages` and `activatePage` or explicit `pageID` values
  when they need deterministic targeting

## Runtime, Debug, and Cookie Interplay

The debug lane and the cookie API are separate concerns.

- `getDebugStatus` reports whether the optional CEF remote debugging lane is
  enabled through `ghodex-browser-remote-debug-port`
- remote debugging is a diagnostics lane only; it is not required for the
  cookie API
- the cookie commands work through the product control plane even when the debug
  lane is disabled

## Recommended Caller Pattern

For deterministic cookie work:

1. `listTabs`
2. choose `browserTabID`
3. `listPages`
4. choose or activate `pageID`
5. `loadURL` if needed
6. `getCookies` to inspect current visible state
7. `setCookie`, `deleteCookie`, or `clearCookies`
8. `getCookies` again to verify the post-mutation visible state

## Related Documents

- `browser-tab-command-protocol.md`
- `browser-tab-acceptance-matrix.md`
- `cef-browser-smoke-validation.md`
