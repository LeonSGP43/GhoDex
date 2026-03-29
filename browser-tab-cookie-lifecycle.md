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

External profile source mode:

- env override: `GHODEX_CEF_PROFILE_PATH`
- mirrored defaults keys: `BrowserCEFProfilePath`, `BrowserCEFProfileMode`,
  `BrowserCEFProfileSourcePath`
- config keys: `ghodex-browser-profile-path`, `ghodex-browser-profile-mode`
- when a profile source is present, GhoDex resolves one of four consumption
  modes before CEF starts and then passes the effective profile directory as
  `user-data-dir` + `profile-directory`

### External profile consumption modes

When `ghodex-browser-profile-path` points at an existing Chrome/Chromium profile
directory, Browser currently supports these modes:

| Mode | Effective profile path | Sync behavior | Locked Chrome behavior |
| --- | --- | --- | --- |
| `direct` | The selected source profile itself | No mirror copy | Refuses to refresh anything; Browser uses the source path exactly as configured. |
| `mirror-latest` | `~/Library/Application Support/GhoDex/CEF/ProfileMirrors/<sanitized-source>/<leaf-profile>` | Re-copies the full Chrome user-data root into GhoDex's mirror container before each resolution | Falls back to the last successful mirror snapshot if Chrome still owns the source root. |
| `mirror-once` | Same managed mirror path as above | Creates the mirror only if it does not already exist | Reuses the existing mirror snapshot when Chrome is live. |
| `mirror-manual` | Same managed mirror path as above | Reuses the current mirror snapshot until the user explicitly refreshes it | Keeps the last mirror; manual refresh fails until the source root is no longer live-locked. |

The mirror implementation intentionally copies the full Chrome user-data root
around the selected profile so shared files like `Local State` stay aligned with
the mirrored profile leaf that CEF actually opens.

Concrete evidence from the current workspace:

- profile round-trip artifact:
  `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/smoke-result.json`
- defaults snapshot:
  `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/defaults-snapshot.plist`
- live startup log with external profile wiring:
  `/Users/leongong/Desktop/LeonProjects/gho_workspace/smoke-cef-browser-20260319/app-launch.log`
- restart-based cookie persistence proof for both managed and external modes:
  `/tmp/ghodex-browser-cookie-persistence-acceptance-rerun.json`
- isolated per-mode profile acceptance proofs recorded on March 23, 2026:
  `/tmp/ghx-direct-acceptance.json`,
  `/tmp/ghx-mirror-latest-acceptance.json`,
  `/tmp/ghx-mirror-once-acceptance.json`,
  `/tmp/ghx-mirror-manual-acceptance.json`
- aggregate all-mode acceptance proof using isolated `HOME` plus dedicated
  source profiles:
  `/tmp/ghx-profile-mode-acceptance.json`
- March 24, 2026 macOS keychain root-cause artifact for Google-login mirror
  false negatives:
  `/tmp/ghx-google-keychain-root-cause.json`
- March 25, 2026 copied-`Profile 10` Google/Gmail mirror acceptance using an
  isolated `GHODEX_BROWSER_APP_SUPPORT_ROOT`:
  `/tmp/ghxgm7-ahignfzj/result.json`

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

1. Browser startup resolves `ghodex-browser-profile-path`,
   `ghodex-browser-profile-mode`, `BrowserCEFProfilePath`,
   `BrowserCEFProfileMode`, `BrowserCEFProfileSourcePath`, or
   `GHODEX_CEF_PROFILE_PATH`.
2. `BrowserPaths` validates the selected source profile and then resolves the
   effective launch path according to the active mode.
3. In direct mode, CEF launches against the source Chromium profile itself. In
   any mirror mode, CEF launches against GhoDex's managed mirror snapshot.
4. Browser tabs then reuse the cookie jar that exists inside that effective
   launch path.
5. External cookie commands still only operate on `document.cookie`, even when
   the underlying profile also contains HTTPOnly or otherwise hidden cookies.

### Browser-signin runtime sanitization boundary

The current external-profile runtime path now treats Chrome browser-signin data
as a different layer from reusable web-session state.

When GhoDex prepares the runtime-owned copy of a mirrored/direct Chrome
profile, it still preserves the profile's web state:

- cookie databases after os_crypt rewrap
- service-worker, IndexedDB, storage, and page-owned profile data
- the Google/Gmail page session that those cookies and storage entries express

But it intentionally strips Chrome-browser-signin-only artifacts from the
runtime-owned copy:

- `Web Data.token_service`
- `gaia_cookie` and related browser-signin preference/account keys
- `Accounts`
- `Account Web Data`
- `Login Data For Account`
- `Sync Data`
- `trusted_vault.pb`
- copied Google profile avatar assets that belong to Chrome's browser-account UI

Decision trail:

- GhoDex needs the copied web session, not Chrome's browser-signin client
- Chrome-browser-signin stores expect Chrome-owned OAuth/account plumbing that
  GhoDex does not ship
- preserving cookies/storage while removing those browser-account stores keeps
  Google web login reusable without making the runtime-owned mirror depend on
  Chrome-only account services

Concrete restart behavior proven by the March 23, 2026 acceptance artifacts:

- `direct`: the second launch sees the same cookie that the first launch wrote
  into the selected source profile
- `mirror-latest`: the second launch intentionally starts without the first
  launch's cookie because the mirror is rebuilt from the updated source root
- `mirror-once`: the second launch sees the first launch's cookie because the
  existing mirror snapshot is reused
- `mirror-manual`: the second launch sees the first launch's cookie because the
  mirror stays frozen until the user explicitly refreshes it

### Invalid override behavior

Config-driven runtime/profile overrides now go through existing-directory
validation before they are mirrored into Browser-related `UserDefaults`.

Current behavior:

- valid existing directories are mirrored and become effective candidates
- explicit empty config values still clear the override
- invalid config-backed overrides are removed from the mirrored defaults entry
  and logged so the fallback is observable
- live Chrome locks on mirrored sources do not destroy the last good mirror
  snapshot; `mirror-latest` and `mirror-once` can still fall back to that
  existing snapshot
- the Browser runtime then continues with the remaining effective source,
  usually the managed defaults

### Isolated test root notes

`BrowserPaths` also supports `GHODEX_BROWSER_APP_SUPPORT_ROOT`, which moves the
Browser tab app-support root used for paths like the local IPC socket and the
managed runtime location chosen by `BrowserPaths`.

The current CEF bridge now resolves its own GhoDex-managed runtime/profile/log
roots from that same app-support override, while still reading the active
external-profile selection from:

- `GHODEX_CEF_ROOT`
- `GHODEX_CEF_PROFILE_PATH`
- `BrowserCEFRuntimePath`
- `BrowserCEFProfilePath`
- `BrowserCEFRemoteDebugPort`

So an isolated app-support root cleanly relocates the GhoDex-owned CEF runtime
and profile roots, but the caller still has to route the active external
Chrome-profile selection through those env or `UserDefaults` inputs.

For the current aggregate mirror/direct harness, each mode also gets its own
isolated `HOME`, dedicated source profile tree, fresh local cookie test server,
and a `Library/Keychains` symlink back to the host login keychain. That keeps
one slow or wedged mode from contaminating the next mode's acceptance evidence
while still preserving the macOS keychain view that Chrome-backed cookie
decryption depends on.

### macOS keychain constraint for real Chrome cookies

Real Chrome Google-login cookies on macOS are not a plain "copy the SQLite file
and you're done" case. The copied profile still depends on Chromium's os_crypt
layer reaching a valid default keychain during Browser startup.

Concrete false-negative evidence recorded on March 24, 2026:

- `/tmp/ghx-google-direct-7mkio_j3/app.log` showed `Encryption is not available`
  plus an invalid `cache_path` fallback while probing a detached copy of
  `Profile 10`
- unified system logs for that run showed `SecItemAdd` / `SecItemCopyMatching`
  failures with macOS error `-25307`
- `/tmp/ghx-google-keychain-root-cause.json` demonstrates why: an empty
  isolated `HOME` has no default keychain, while the same isolated `HOME`
  immediately regains a default keychain when `Library/Keychains` is linked back
  to the user's real keychain directory

Decision trail:

- treat `Encryption is not available` from an isolated `HOME` as a harness bug
  first, not as proof that mirror/direct can never reuse Chrome-authenticated
  state
- preserve the host keychain view in isolated acceptance before making any final
  product-level claim about Google-login reuse
- keep mirror behavior unchanged until the acceptance environment is no longer
  failing earlier at macOS keychain discovery

Follow-on evidence after those harness fixes:

- `/tmp/ghxgm7-ahignfzj/result.json` now shows the copied logged-in `Profile 10`
  opening `https://www.google.com/` with `signedInHint = true` and
  `https://mail.google.com/mail/u/0/#inbox` with
  `Inbox (18) - yuan80060@gmail.com - Gmail`
- that acceptance ran under an isolated `GHODEX_BROWSER_APP_SUPPORT_ROOT`, so it
  did not need to touch the user's live app-support tree or kill the user's app
- the remaining Chrome warning in `cef.log` is about Desktop Identity
  Consistency/browser-signin OAuth credentials; it is now non-blocking for the
  copied web session reuse that Browser actually needs

## API Semantics

The stable external protocol version is `browser.tab.v1`.

Compatibility note:

- `browser.context.v2` now documents the top-level object as `browserContext`
- current `browserTabID` values and `browserContextID` values resolve to the
  same live controller/context object
- cookie commands are still page-targeted today, but their durable isolation
  boundary is expected to move toward Browser Context ownership as the control
  plane expands beyond document-visible cookie state

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
- when `frameName` is provided, the cookie helper executes in that named frame's
  JavaScript context
- even with `frameName`, cookie scope is still determined by the document/origin
  that owns `document.cookie`, not by a separate frame-private cookie jar
- results are scoped to the selected page's current `document.cookie` view

Recommended client guidance for iframe-heavy pages:

- pass `browserTabID`
- pass explicit `pageID`
- pass the latest `documentRevision`
- pass `frameName` after discovering it through `listFrames`

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

- results can differ across pages in the same Browser context if they are on
  different origins
- callers should use `listPages` and `activatePage` or explicit `pageID` values
  when they need deterministic targeting inside one context

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

1. `listContexts` or `listTabs`
2. choose `browserContextID` or compatibility `browserTabID`
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
