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
- runtime settings now explicitly describe the managed/custom runtime media
  boundary instead of implying Chrome-like codec parity from the default CEF
  bundle
- popup/new-window routing is now externally visible through the public browser
  event broker instead of being trapped in private logs only
- download, file dialog, JS dialog, permission, HTTP auth, and certificate
  prompt handlers
- page-level Browser control API over IPC and AppleScript
- disposition-aware popup routing across current-page load, page tab, Browser
  window targets, and first-level popup/OAuth hosting with working opener
  semantics

What is still not enough for "normal browser" parity:

- external/mirror mode intentionally disables several Chrome-owned services
- H.264 / AAC media parity is still incomplete even after a fresh isolated
  managed/external probe
- several shipped browser-service handlers are code-complete but not yet
  acceptance-backed

## Risk Tiers

### Tier 0: Blocks Normal Browser Semantics

#### 1. H.264 / broader media-codec parity is still incomplete

Why this matters:

- many real sites and anti-bot stacks treat media-capability mismatches as a
  strong browser-quality signal
- a browser that cannot expose expected codec support is still visibly unlike
  normal Chrome even when WebGL and popup routing are fixed

Evidence:

- `browser-tab-acceptance-matrix.md` already records
  `VIDEO_CODECS WARN h264: ""` in the mirrored-profile fingerprint lane
- the fresh isolated managed lane in
  `/tmp/ghx-browser-media-debug-acceptance-postfix.json`
  reports `h264_baseline = ""`, `mp4_aac = ""`,
  `MediaSource.isTypeSupported(...) = false`, and
  `PipelineStatus::DEMUXER_ERROR_NO_SUPPORTED_STREAMS`
- the same combined artifact records the isolated external lane with the same
  H.264/AAC failure shape under an external profile

Code path:

- media/codec behavior still depends on the embedded Chromium runtime and the
  launch/runtime surface in `macos/Sources/Features/Browser/CEF/GhoDexCEFBridge.mm`

Conclusion:

- WebGL parity improved a major visible surface, but media capability is still
  a confirmed normal-browser blocker in the current runtime
- the product now exposes this boundary in the Browser runtime settings UI, but
  the underlying codec gap is still real until a codec-enabled CEF runtime is
  supplied

### Tier 1: Product Boundary Choices That Prevent Full Chrome Equivalence

#### 2. External/mirror mode still launches with an intentionally reduced Chrome
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

#### 3. Browser-signin parity remains intentionally out of scope

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

#### 4. Several browser-service handlers are implemented but not acceptance-backed

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

#### 5. Popup requests are now externally observable across both routed tabs and
dedicated popup hosts, but still need a trusted-gesture end-to-end artifact

Why this matters:

- this is not a browsing blocker by itself
- it does make automated acceptance and diagnosis harder exactly where popup and
  OAuth behavior are already weakest

Evidence:

- `BrowserExternalEventBroker` now maps `.openURLInNewTabRequested` into the
  public `popupRequest` event kind instead of dropping it
- dedicated native popup-host windows now emit `popupRequest` too through the
  new `.popupWindowHosted` bridge path instead of staying invisible
- `BrowserTabModel.handle(_:from:)` now enriches popup events with
  `routingTarget`, `resultPageID`, `resultBrowserTabID`, `resultIsActive`, and
  `resultVisibilityState`
- `macos/Tests/Browser/BrowserPopupEventTests.swift` locks the payload contract
  for page-tab, Browser-window, and dedicated-popup-host outcomes
- `scripts/browser_popup_event_acceptance.py` now provides an isolated harness
  scaffold for future popup event artifacts

Conclusion:

- the specific broker observability gap is closed
- remaining work is evidence quality: a fully automated site-driven artifact is
  still blocked because `browser.tab.v1 click` currently uses DOM
  `element.click()` instead of a trusted native browser gesture, so a pure IPC
  harness cannot yet force real popup gestures reliably

#### 6. Remote-debug hardening is now runtime-verified for isolated acceptance

Why this matters:

- a "debug lane is opt-in" contract is only credible if isolated acceptance can
  prove it without inheriting stale host defaults

Evidence:

- `/tmp/ghx-browser-media-debug-managed.json` now records `enabled = false`
  before and after `newTab`, with `remote_debug_port = 0`
- `/tmp/ghx-browser-media-debug-external.json` records the same default-closed
  result for the external-profile lane

Conclusion:

- this gap is closed for isolated acceptance. The remaining blocker is media
  parity, not accidental default-open remote debugging

## What This Means

If the target is:

- "a stable internal browser that can reuse Chrome web state and browse normal
  sites reasonably well"
  Current state: close. Popup/OAuth routing is now materially where it needs to
  be, but media parity and a few remaining service-surface gaps still keep the
  claim from being strong.

- "a browser that is basically Chrome with the same profile and service layer"
  Current state: not reached. The external-profile launch policy still
  intentionally removes browser-signin/sync/extensions/media-router and related
  Chrome service surfaces.

- "a browser that does not look like an obviously stripped automation shell"
  Current state: improved, but still not complete. WebGL parity, popup routing,
  and default-closed isolated debug proof are now in place; H.264/media
  capability and reduced Chrome-owned services remain the highest-confidence
  visible gaps.

## Recommended Next Sequence

1. Run a media-capability acceptance lane focused on H.264/video support and
   other high-signal fingerprint surfaces.
2. Add dedicated acceptance for the remaining permission/auth/dialog surfaces
   that are currently code-backed but not end-to-end proven.
3. Decide explicitly whether external/mirror mode is meant to stay a
   "web-session reuse" product or evolve toward fuller Chrome-service
   equivalence. That decision should control whether the current
   `disable-*`/`allow-browser-signin=false` launch policy stays in place.
4. Add a fresh isolated verification lane proving the debug port stays closed
   when unset, so the hardening work is runtime-backed and not only build-backed.
