# Browser Tab Full-Pass Plan

## Goal

Close the remaining acceptance gaps so the embedded browser tab feature can be
accepted as a complete, externally controllable browser runtime instead of a
good-but-incomplete `browser.tab.v1`.

The full-pass target is:

- cookie persistence is proven and controllable through the external API
- profile and runtime overrides resolve consistently without silent fallback
- a config-gated debug lane exists, stays off by default, and is documented as
  diagnostics only
- the external API can target browser tabs, pages, and frames with stable
  semantics
- protocol and acceptance docs explain the behavior, limits, and verification
  evidence

## Current Acceptance Gaps

### 1. Cookie Lifecycle

- session-cookie persistence is enabled in CEF, but not yet proven with a
  durable restart test
- the external API does not yet expose cookie inspection or mutation commands
- the protocol guide does not explain cookie scope, persistence, or profile
  interaction

### 2. Debug Lane

- the architecture doc still marks config-gated remote debugging as pending
- current external events cover console/network/snapshot observation, but not a
  formal developer diagnostics lane
- the docs do not yet distinguish between the product control API and the
  optional diagnostics surface

### 3. Page and Frame Targeting

- the architecture already defines `pageID`, `frameName`, and
  `documentRevision`, but the external protocol still routes mainly by
  `browserTabID`
- `newTab` currently creates a new Browser window/controller, while internal
  page-tab creation is a different path
- revision-based stale-response protection is not yet enforced at the external
  protocol boundary

### 4. Profile and Runtime Override Consistency

- UI-driven Browser settings validate their paths before writing config
- config-driven sync currently normalizes paths but can still mirror invalid
  overrides into `UserDefaults`, leaving CEF to silently ignore them later
- the effective runtime/profile state therefore needs one final consistency pass
  before the deeper acceptance work

## Execution Order

### Track 0: Profile and Runtime Consistency

- [ ] `fix(browser): validate profile/runtime overrides during config sync`
  - validate config-driven profile/runtime overrides before mirroring them into
    `UserDefaults`
  - keep explicit empty values as "clear the override" instead of falling back
  - log invalid config-driven overrides so the fallback is observable
  - verify with `swiftlint` and macOS app builds

### Track 1: Cookie Acceptance and API

- [ ] `test(browser): add cookie persistence acceptance harness`
  - write a cookie
  - restart the app
  - read the cookie back
  - cover managed and external profile modes
- [ ] `feat(browser): add cookie inspection commands`
  - add `getCookies`
  - support basic filters such as `url`, `domain`, and `name`
- [ ] `feat(browser): add cookie mutation commands`
  - add `setCookie`
  - add `deleteCookie`
  - add `clearCookies`
- [ ] `docs(browser): document cookie lifecycle and API semantics`

### Track 2: Config-Gated Debug Lane

- [ ] `feat(debug): add config-gated remote debugging setting`
  - keep it off by default
  - only enable when explicitly configured
- [ ] `feat(debug): expose debug status through browser.tab.v1`
  - add `getDebugStatus`
  - report whether diagnostics are active and on which local port
- [ ] `docs(debug): document debug lane as diagnostics only`

### Track 3: Page/Frame Protocol Upgrade

- [ ] `feat(browser): add external page discovery commands`
  - add `listPages`
  - add `getActivePage`
  - optionally add `activatePage`
- [ ] `feat(browser): add page-aware external command routing`
  - let external commands target a specific `pageID`
- [ ] `feat(browser): add frame-aware targeting`
  - add frame discovery
  - allow page-runtime and inspect commands to scope to a frame
- [ ] `fix(browser): enforce document revision guards for external commands`
- [ ] `feat(browser): promote core DOM actions to first-class external commands`
  - `query`
  - `click`
  - `typeText`
  - `waitForSelector`
  - `getText`
  - `getAttributes`
  - `getBoundingBox`
  - `getDOMSnapshot`

### Track 4: Final Docs and Acceptance Matrix

- [ ] `docs(browser): expand browser.tab.v1 protocol guide`
  - cookie commands
  - debug lane behavior
  - page/frame routing
  - `documentRevision`
  - `newTab` vs internal page-tab semantics
- [ ] `docs(browser): add acceptance matrix for cookie/profile/debug/api`
  - map each requirement to a command, config, and verification artifact

## Full-Pass Acceptance Gate

Treat the browser tab feature as fully accepted only when all of these are
true:

- cookie persistence has an automated restart proof
- cookie state is externally readable and writable
- invalid profile/runtime overrides no longer silently drift from the effective
  CEF state
- debug diagnostics are explicitly gated, off by default, and documented
- external commands can target tabs, pages, and frames with revision-aware
  behavior
- the protocol guide and acceptance docs both explain the supported commands,
  event behavior, limits, and verification evidence
