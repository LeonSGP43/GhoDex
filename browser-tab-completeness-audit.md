# Browser Tab Completeness Audit

## Purpose

This document records the current browser-completeness baseline after the real
popup-hosting fix on March 25, 2026.

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
- disposition-aware popup routing across current-page load, page tab, Browser
  window targets, and first-level popup/OAuth hosting with working opener
  semantics

What is still not enough for "normal browser" parity:

- external/mirror mode intentionally disables several Chrome-owned services
- media/fingerprint acceptance is still incomplete
- several shipped browser-service handlers are code-complete but not yet
  acceptance-backed
- popup-hosted follow-up opens still fall back to `NSWorkspace`

## Risk Tiers

### Tier 0: Blocks Normal Browser Semantics

#### 1. Popup-hosted follow-up opens are still not fully internalized

Why this matters:

- the first popup hop now behaves like a real browser popup, but a popup-hosted
  page can still delegate later open requests out to the system browser instead
  of staying inside GhoDex
- multi-hop auth/payment flows sometimes chain more than one popup or use
  follow-up open requests after the first child is already live

Evidence:

- isolated runtime artifact `/tmp/ghx-popup-oauth-final-2d9a943a.json`
- settled opener state now reports `lastOpenResult.returnedObject = true`
- popup result reports `openerPresent = true`
- opener page receives the `oauth-complete` `postMessage`
- popup self-close is reflected back to the opener with `popupClosedFlag = true`
- popup-host follow-up requests from `GhoDexCEFPopupWindowController` still call
  `NSWorkspace.sharedWorkspace openURL:`

Code path:

- `OnBeforePopup(...)` now keeps the real popup client path in
  `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm`
- `GhoDexCEFPopupWindowController` in the same file still delegates nested
  follow-up opens through `NSWorkspace`

Conclusion:

- the first-level popup/OAuth blocker is now fixed
- the remaining popup gap is narrower: nested popup-host follow-up routing still
  needs to stay inside the product instead of escaping to the system browser

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
  Current state: close. First-level popup/OAuth semantics are now fixed, but
  media parity and a few remaining service-surface gaps still keep the claim
  from being strong.

- "a browser that is basically Chrome with the same profile and service layer"
  Current state: not reached. The external-profile launch policy still
  intentionally removes browser-signin/sync/extensions/media-router and related
  Chrome service surfaces.

- "a browser that does not look like an obviously stripped automation shell"
  Current state: improved, but still unproven. WebGL parity and first-level
  popup opener semantics are fixed; H.264/media capability and reduced
  Chrome-owned services remain the highest-confidence visible gaps.

## Recommended Next Sequence

1. Internalize nested popup-host follow-up routing so popup-launched opens do
   not escape to `NSWorkspace`.
2. Run a media-capability acceptance lane focused on H.264/video support and
   other high-signal fingerprint surfaces.
3. Add dedicated acceptance for the remaining permission/auth/dialog surfaces
   that are currently code-backed but not end-to-end proven.
4. Decide explicitly whether external/mirror mode is meant to stay a
   "web-session reuse" product or evolve toward fuller Chrome-service
   equivalence. That decision should control whether the current
   `disable-*`/`allow-browser-signin=false` launch policy stays in place.
5. Add a fresh isolated verification lane proving the debug port stays closed
   when unset, so the hardening work is runtime-backed and not only build-backed.
