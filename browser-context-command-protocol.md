# Browser Context Command Protocol

## Purpose

`browser.context.v2` is the forward-looking Browser Control contract for GhoDex.
It keeps the existing local IPC and AppleScript transports, but fixes the
object-model boundary that `browser.tab.v1` blurred.

The top-level automation object is now:

- `browserContext`: one isolated browser identity/runtime container
- `page`: one internal browsing tab inside a context
- `frame`: one addressable frame inside a page

For the current implementation slice:

- one `BrowserTabController` maps to one `browserContext`
- `BrowserTabModel.pages` are the internal `page` objects
- legacy `browserTabID` and new `browserContextID` currently resolve to the same
  stable controller ID

## Object Mapping

| Old term | Actual runtime object | New term |
| --- | --- | --- |
| Browser tab | top-level window/controller | Browser Context |
| internal page tab | one `BrowserPageState` inside the controller | page |
| frame | CEF frame inside a page | frame |

## Envelope Shape

`browser.context.v2` reuses the existing request/response envelope and transport
adapters. The main changes are versioning and terminology:

```json
{
  "id": "B5B5A4DE-1C7E-4B5A-9E8E-5D9C64A0D2C1",
  "version": "browser.context.v2",
  "command": "newPageInContext",
  "browserContextID": "browser-tab-1",
  "browserTabID": null,
  "pageID": null,
  "frameName": null,
  "documentRevision": null,
  "payload": {
    "url": "https://example.com"
  }
}
```

Field notes:

- `browserContextID` is the preferred top-level identifier for v2 callers
- `browserTabID` is preserved as a compatibility alias
- `pageID` still targets one page inside the resolved context
- `documentRevision` remains the stable stale-document guard for page commands

`newContext` policy payload (optional, defaults shown):

- `profilePolicy`: `managed` (default) or `isolated`
- `egressPolicy`: `system` (default), `direct`, `named-proxy`, `local-gateway`
- `egressTarget`: required when `egressPolicy` is `named-proxy` or
  `local-gateway`
- `fingerprintPolicy`: `native` (default), `hardened-normal`, `custom-stable`
- `popupInheritancePolicy`: `inherit-source-context` (default) or
  `isolate-popup`

Context summary payload (`listContexts` / `getContext` / `newContext`) now
includes:

- `contextPolicy`: the resolved policy object with defaults applied

## Core Commands

Context lifecycle:

- `listContexts`
- `getContext`
- `newContext`
- `activateContext`
- `closeContext`

Page lifecycle inside one context:

- `listPages`
- `newPageInContext`
- `getActivePage`
- `activatePage`
- `closePage`
- `listFrames`

Page navigation and runtime:

- `loadURL`
- `goBack`
- `goForward`
- `reload`
- `evaluateJavaScript`
- `query`
- `click`
- `typeText`
- `waitForSelector`
- `getText`
- `getAttributes`
- `getBoundingBox`
- `getDOMSnapshot`
- `runDOMBatch`

State and events:

- `getCookies`
- `setCookie`
- `deleteCookie`
- `clearCookies`
- `cancelDownload`
- `resolveDialog`
- `resolvePermission`
- `resolveAuth`
- `resolveCertificate`
- `subscribeEvents`
- `drainEvents`
- `unsubscribeEvents`

Current externally observable runtime-service event kinds on that shared event
stream:

- `download`
- `javaScriptDialog`
- `permissionRequest`
- `authenticationRequest`
- `certificateWarning`

## Compatibility Rules

- `browser.tab.v1` remains supported
- `listTabs` is the compatibility view of `listContexts`
- `newTab` is the compatibility alias for `newContext`
- v1 and v2 both route through the same IPC and AppleScript entrypoints
- popup routing, page IDs, and frame targeting continue to work on top of the
  same underlying `documentRevision` addressing model

## Current Boundary

This v2 slice only fixes the control-plane object model. It does not yet add
true per-context proxy, fingerprint, storage, or profile policy separation in
CEF runtime configuration. Those remain the next layers after the object model
and lifecycle API are stable.

`contextPolicy` is currently a first-class control-plane metadata boundary:
callers can set and read it per context, but runtime enforcement is still a
follow-up slice.

## Acceptance Evidence

Current isolated protocol proof:

- harness:
  `scripts/browser_context_protocol_acceptance.py`
- artifact:
  `/tmp/ghx-browser-context-protocol-acceptance.json`

What that proof currently covers:

- `browser.context.v2` context/page lifecycle commands
- `goBack`, `goForward`, and `reload` command acceptance on a live page
- `browser.tab.v1` compatibility routing for `listPages` against a v2-created
  context
- `browser.tab.v1` `newTab` creating a top-level Browser context that is then
  visible through `browser.context.v2` `listContexts`

The runtime-service event kinds above are part of the same shared event stream
and currently have unit coverage for kind mapping and payload shape. Runtime
prompt resolution now extends that same surface for JS dialogs, permission
prompts, HTTP auth, and certificate warnings.

## Runtime Prompt Resolution

These commands target a live page inside a context and resolve a previously
emitted runtime prompt by `requestID`.

- `resolveDialog`
  payload:
  - `requestID`
  - `accepted` as `true` or `false`
  - `userInput` for prompt dialogs when accepting custom text
- `resolvePermission`
  payload:
  - `requestID`
  - `result` as `allow`, `deny`, or `dismiss`
- `resolveAuth`
  payload:
  - `requestID`
  - `accepted` as `true` or `false`
  - `username` when accepting credentials
  - `password` when accepting credentials
- `resolveCertificate`
  payload:
  - `requestID`
  - `accepted` as `true` or `false`

Each command returns an acknowledgement containing:

- `requestID`
- `kind`
- `resolved`

Requested runtime prompt events now include `requestID` in their payload so the
external client can bind the follow-up resolve command to the paused runtime
handler.

## Download Control

`cancelDownload` targets a live page inside a context and cancels an in-flight
download by `downloadID`.

Payload:

- `downloadID`

Return payload:

- `downloadID`
- `accepted`
- `operation` as `cancelDownload`

Cancellation does not invent a new event kind. The existing `download` event
stream remains the source of truth for lifecycle confirmation and should emit a
follow-up `phase=canceled` event when the runtime finishes canceling the
download.
