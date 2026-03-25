# Browser Tab Completeness Audit

## Purpose

This document records the current browser-completeness baseline after the popup
disposition routing fix on March 25, 2026.

It answers a narrower question than the full acceptance matrix:

- can the built-in browser be treated as a long-term, normal Chrome-like
  browser today?
- which gaps are product-boundary choices vs real correctness/completeness
  blockers?
- what should be fixed next if the target is "usable like a normal browser"
  instead of "good enough for controlled page automation"?

## Current State

What is materially working now:

- managed CEF runtime installation and activation
- managed, direct, and mirrored profile selection
- mirrored Chrome web-session reuse, including the isolated Google/Gmail proof
- download, file dialog, JS dialog, permission, HTTP auth, and certificate
  prompt handlers
- page-level Browser control API over IPC and AppleScript
- disposition-aware popup routing across current-page load, page tab, and
  Browser window targets

What is still not enough for "normal browser" parity:

- popup/opener/OAuth semantics are still broken at runtime
- external/mirror mode intentionally disables several Chrome-owned services
- media/fingerprint acceptance is still incomplete
- several shipped browser-service handlers are code-complete but not yet
  acceptance-backed

## Risk Tiers

### Tier 0: Blocks Normal Browser Semantics

#### 1. Real popup opener semantics are still broken

Why this matters:

- real OAuth and many identity/payment flows rely on `window.open(...)`,
  `window.opener`, and `postMessage` between opener and child
- a browser that opens the page but loses opener semantics is not equivalent to
  Chrome from the site's point of view

Evidence:

- isolated runtime artifact `/tmp/ghx-popup-oauth-accept-d396923d.json`
- opener result: `returnedObject = false`
- popup result: `openerPresent = false`
- opener page result: `messages = []`
- popup close still works, proving the child Browser window exists but is not a
  true opener-linked popup

Code path:

- `OnBeforePopup(...)` still cancels the real popup client path in
  `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm`
- Swift then recreates the target as a new Browser page/window through
  `macos/Sources/Features/Browser/BrowserTabModel.swift` and
  `macos/Sources/Features/Browser/BrowserTabController.swift`

Conclusion:

- the recent popup-routing fix corrected destination policy, but not browser
  window semantics
- if the product goal is "normal browser", the next implementation must keep a
  real popup browser relationship instead of canceling and reconstructing it

#### 2. H.264 / broader media-codec parity is still unproven and likely
incomplete

Why this matters:

- many real sites and anti-bot stacks treat media-capability mismatches as a
  strong browser-quality signal
- a browser that cannot expose expected codec support is still visibly unlike
  normal Chrome even when WebGL is fixed

Evidence:

- `browser-tab-acceptance-matrix.md` already records
  `VIDEO_CODECS WARN h264: ""` in the mirrored-profile fingerprint lane
- only the WebGL/GPU parity lane is currently acceptance-backed

Conclusion:

- WebGL parity improved a major visible surface, but media capability is still
  a remaining normal-browser blocker until proven otherwise

### Tier 1: Product Boundary Choices That Prevent Full Chrome Equivalence

#### 3. External/mirror mode still launches with an intentionally reduced Chrome
service surface

Why this matters:

- this is not accidental breakage; it is a deliberate compatibility/safety
  tradeoff
- if the product target is "full Chrome-profile equivalence", these switches
  mean the target state is still not reached

Current external-profile launch policy:

- `use-mock-keychain`
- `allow-browser-signin=false`
- `disable-background-networking`
- `disable-component-update`
- `disable-default-apps`
- `disable-extensions`
- `disable-sync`
- `disable-features=SegmentationPlatformFeature,OptimizationGuideModelDownloading,MediaRouter`

Code path:

- `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm`

Interpretation:

- for "reuse web cookies/session safely inside GhoDex", this is acceptable and
  documented
- for "behave like full Chrome with the same profile-backed service layer", it
  is not sufficient

#### 4. Browser-signin parity remains intentionally out of scope

Why this matters:

- the runtime profile preparation explicitly strips browser-account and
  Chrome-signin state while preserving web-session state
- this is the correct move for the current product, but it means the browser is
  still not a drop-in Chrome clone

Evidence:

- runtime-signin sanitization logic in
  `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm`
- existing docs already state that Google web reuse is preserved while Chrome
  browser-signin remains disabled

Conclusion:

- if the target is "normal embedded browser", this is fine
- if the target is "same profile, same Chrome service plane", this is still a
  hard boundary

### Tier 2: Acceptance and Observability Gaps

#### 5. Several browser-service handlers are implemented but not acceptance-backed

Implemented surfaces:

- file dialogs
- downloads
- JS dialogs
- before-unload dialogs
- media and generic permissions
- HTTP auth
- certificate warning prompts

What is still missing:

- dedicated end-to-end acceptance for everything except downloads
- real multi-step site flows proving these handlers behave correctly under
  navigation and popup pressure

Conclusion:

- code coverage here is materially better than before, but "implemented" still
  exceeds "proven"

#### 6. Popup requests are not externally observable through the public event broker

Why this matters:

- this is not a browsing blocker by itself
- it does make automated acceptance and diagnosis harder exactly where popup and
  OAuth behavior are already weakest

Evidence:

- `BrowserExternalEventBroker.externalKind(for:)` drops
  `.openURLInNewTabRequested`

Conclusion:

- keeping popup/open-window events invisible externally weakens the product's
  own ability to prove and debug popup correctness

#### 7. Remote-debug hardening is build-verified but still lacks a fresh runtime proof

Why this matters:

- the command-line policy to strip accidental remote-debug switches is a good
  hardening move
- however, the latest work only proved that the app builds, not that a new
  isolated runtime artifact confirms the lane stays closed when unset

Conclusion:

- this is a verification gap, not currently a correctness regression

## What This Means

If the target is:

- "a stable internal browser that can reuse Chrome web state and browse normal
  sites reasonably well"
  Current state: close, but popup/OAuth and media parity still block that claim
  from being strong.

- "a browser that is basically Chrome with the same profile and service layer"
  Current state: not reached. The external-profile launch policy still
  intentionally removes browser-signin/sync/extensions/media-router and related
  Chrome service surfaces.

- "a browser that does not look like an obviously stripped automation shell"
  Current state: improved, but still unproven. WebGL parity is fixed; popup
  opener semantics and H.264/media capability remain the highest-confidence
  visible gaps.

## Recommended Next Sequence

1. Replace popup reconstruction with a true CEF popup ownership model so child
   windows preserve `window.opener` and `postMessage` semantics.
2. Add a dedicated popup/OAuth acceptance harness and make it part of the
   durable evidence set.
3. Run a media-capability acceptance lane focused on H.264/video support and
   other high-signal fingerprint surfaces.
4. Decide explicitly whether external/mirror mode is meant to stay a
   "web-session reuse" product or evolve toward fuller Chrome-service
   equivalence. That decision should control whether the current
   `disable-*`/`allow-browser-signin=false` launch policy stays in place.
5. Add dedicated acceptance for permission/auth/dialog flows that are currently
   only code-backed.
