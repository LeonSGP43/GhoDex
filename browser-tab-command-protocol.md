# Browser Tab Command Protocol

## Purpose

`browser.tab.v1` is the versioned external control contract for GhoDex browser
 tabs. External clients should treat this document as the product-facing API for
 browser control sessions, and treat the internal Swift/CEF implementation as an
 implementation detail.

Compatibility note:

- `browser.tab.v1` remains supported for existing clients
- the underlying top-level object is now documented as a Browser Context
- `browser.tab.v1` identifiers still resolve to that same top-level context
- the forward-looking object model is documented in
  `browser-context-command-protocol.md`

The protocol is designed for:

- low-latency local control over a running Browser tab
- stable request/response envelopes across transport adapters
- buffered event subscriptions for lifecycle, console, network, and page
  inspection streams
- future adapters that reuse the same contract instead of inventing one-off
  scripts

## Transports

Two local transports currently speak the same request envelope.

### Local IPC Socket

Preferred for long-lived local sessions.

- Path: `~/Library/Application Support/GhoDex/browser-control.sock`
- When `GHODEX_BROWSER_APP_SUPPORT_ROOT` is set for an isolated test session,
  the socket lives under that alternate app-support root instead
- CLI flag: `--transport=ipc`
- CLI default: `--transport=auto` tries IPC first, then falls back to
  AppleScript
- The IPC and CLI Browser control path does not require
  `macos-applescript = true`; that config gate only applies to the AppleScript
  adapter itself
- Response buffering is capped at 1 MiB per connection
- A client that stops draining large responses can be disconnected without
  affecting other active IPC sessions

### AppleScript Adapter

Compatibility path when the IPC socket is unavailable.

- CLI flag: `--transport=applescript`
- App command: `run browser command protocol <requestJSON>`

## Envelope Shape

Every request is a JSON object with this shape:

```json
{
  "id": "B5B5A4DE-1C7E-4B5A-9E8E-5D9C64A0D2C1",
  "version": "browser.tab.v1",
  "command": "listTabs",
  "browserTabID": null,
  "pageID": null,
  "frameName": null,
  "documentRevision": null,
  "payload": {}
}
```

Field notes:

- `id`: caller-generated UUID used to correlate the response
- `version`: `browser.tab.v1` for compatibility clients
- `command`: one of the supported command names
- `browserTabID`: optional tab identifier; required for tab-specific commands
- `pageID`: optional internal page identifier for page-targeted commands
- `frameName`: optional named-frame target for commands that can address a
  specific frame
- `documentRevision`: optional page precondition; when present, page-targeted
  commands fail if the resolved page has since navigated
- `payload`: string-valued map for command arguments

Every response is a JSON object with this shape:

```json
{
  "id": "B5B5A4DE-1C7E-4B5A-9E8E-5D9C64A0D2C1",
  "version": "browser.tab.v1",
  "ok": true,
  "resultJSON": "{\"tabs\":[]}",
  "error": null
}
```

Field notes:

- `ok=true` means the command completed successfully
- `resultJSON` is itself a JSON-encoded string; callers should decode it as a
  second step
- `error` is a structured object when `ok=false`

## Supported Commands

### Tab Discovery and Creation

- `listTabs`
- `newTab`
- `listPages`
- `getActivePage`
- `activatePage`
- `listFrames`

`listTabs` returns a JSON array of tab summaries:

```json
[
  {
    "id": "browser-tab-1",
    "title": "Example Domain",
    "url": "https://example.com"
  }
]
```

`newTab` returns a single tab summary for the created tab.

Important semantic note:

- `newTab` creates a new Browser window/controller
- in the newer object model, that top-level object is a Browser Context
- `newTab` should now be treated as a compatibility alias for `newContext`
- it does not append an internal page to an existing Browser tab
- use `listPages` / `activatePage` to work with the internal pages that already
  exist inside one Browser tab

`listPages` returns a JSON array of page summaries for one Browser tab:

```json
[
  {
    "id": "E5F4C926-7F1C-466E-A6D9-3A6F6A2F6D4E",
    "title": "Example Domain",
    "url": "https://example.com",
    "isActive": true,
    "documentRevision": 4
  }
]
```

`getActivePage` returns one page summary for the currently selected internal
page.

`activatePage` payload:

```json
{
  "pageID": "E5F4C926-7F1C-466E-A6D9-3A6F6A2F6D4E"
}
```

`activatePage` returns the activated page summary.

`listFrames` returns a JSON array of frame summaries for one Browser page:

```json
[
  {
    "name": "",
    "url": "https://example.com",
    "isMainFrame": true
  },
  {
    "name": "embedded-checkout",
    "url": "https://checkout.example.com/frame",
    "isMainFrame": false
  }
]
```

`listFrames` is page-scoped, so callers should pass the Browser tab plus the
page they want to inspect. Named child frames are addressable through
`frameName`; unnamed child frames are observable in events but are not yet
targetable through the external command envelope.

### Navigation and Runtime

- `getDebugStatus`
- `loadURL`
- `goBack`
- `goForward`
- `reload`
- `getCookies`
- `setCookie`
- `deleteCookie`
- `clearCookies`
- `evaluateJavaScript`
- `runDOMBatch`

### First-Class DOM Commands

- `query`
- `click`
- `typeText`
- `waitForSelector`
- `getText`
- `getAttributes`
- `getBoundingBox`
- `getDOMSnapshot`

`getDebugStatus` payload:

```json
{}
```

`getDebugStatus` returns a JSON object with:

- `enabled`: whether the config-gated CEF remote debugging lane is currently enabled
- `port`: the configured remote debugging port when enabled, otherwise `null`
- `source`: currently `config` or `disabled`
- `cefInitialized`: whether global CEF initialization has completed in this app session
- `runtimeAvailable`: whether this app session can see a usable CEF runtime root

## Diagnostics Lane

The optional CEF remote debugging lane is a diagnostics surface, not the
product contract for Browser automation.

- `browser.tab.v1` remains the primary control API for Browser tabs
- `browser.context.v2` is the new context/page terminology layer for future
  Browser Control clients
- Chromium remote debugging stays disabled by default
- enable it only by setting `ghodex-browser-remote-debug-port` to a positive
  local port in config
- use `getDebugStatus` to confirm whether the current app session actually has
  the diagnostics lane enabled before trying any DevTools/CDP workflow
- if the config key is missing or set to `0`, the diagnostics lane is disabled

Example config:

```toml
ghodex-browser-remote-debug-port = 9222
```

`loadURL` payload:

```json
{
  "url": "https://example.com"
}
```

`evaluateJavaScript` payload:

```json
{
  "script": "JSON.stringify({ title: document.title, href: location.href })"
}
```

`getCookies` payload:

```json
{
  "name": "session_id",
  "domain": "example.com",
  "url": "https://example.com/account"
}
```

Payload notes:

- page-targeted commands may include a top-level `pageID` field in the request
  envelope
- when `pageID` is omitted, the command still targets the active page for
  backward compatibility
- when `pageID` is present, it must be a UUID string returned by `listPages`
- commands that evaluate JavaScript or run DOM/cookie helpers may also include
  top-level `frameName`
- when `frameName` is provided, GhoDex routes the command to that named frame
  instead of the page's main frame
- `frameName` values come from `listFrames`
- `timeoutMS` is accepted as a string payload only for commands that wait, such
  as `waitForSelector`
- page-targeted commands may also include top-level `documentRevision`
- when `documentRevision` is provided, the command fails with
  `stale_document_revision` if the resolved page has already moved to a newer
  document
- all `getCookies` payload fields are optional filters
- `name` matches one visible cookie name exactly
- `domain` matches the current page hostname exactly or by suffix
- `url` matches the active page URL exactly
- the command currently inspects page-visible `document.cookie`, so HTTPOnly
  cookies are intentionally out of scope for `browser.tab.v1`

`getCookies` returns a JSON object with:

- `url`: current page URL
- `domain`: current page hostname
- `cookieHeader`: raw `document.cookie` string
- `appliedFilters`: the normalized non-empty filters that were applied
- `cookies`: decoded `{name,value}` entries after filtering

`setCookie` payload:

```json
{
  "name": "session_id",
  "value": "abc123",
  "path": "/",
  "domain": "example.com",
  "maxAge": "3600",
  "sameSite": "Lax",
  "secure": "true"
}
```

Payload notes:

- `name` is required
- `value` defaults to the empty string when omitted
- `path` defaults to `/`
- `maxAge` must be an integer string when provided
- `sameSite` must be one of `Lax`, `Strict`, or `None`
- `secure` must be `true` or `false` when provided

`deleteCookie` payload:

```json
{
  "name": "session_id",
  "domain": "example.com",
  "path": "/"
}
```

Payload notes:

- `name` is required
- when `path` is omitted, GhoDex tries a small best-effort set of current-page
  path candidates while expiring the cookie

`clearCookies` payload:

```json
{
  "domain": "example.com",
  "path": "/"
}
```

Payload notes:

- all payload fields are optional
- `clearCookies` only clears page-visible cookies from the active page's
  `document.cookie` view
- when `path` is omitted, GhoDex expires each visible cookie across the same
  best-effort current-page path candidates used by `deleteCookie`

`setCookie`, `deleteCookie`, and `clearCookies` return a JSON object with:

- `operation`: `set`, `delete`, or `clear`
- `url`: current page URL
- `domain`: current page hostname
- `cookieHeader`: raw `document.cookie` string after mutation
- `appliedPayload`: the normalized payload GhoDex used for the mutation
- `changedCount`: number of cookie names the command attempted to change
- `changedNames`: cookie names the command targeted
- `cookies`: decoded `{name,value}` entries visible after mutation

### DOM Command Payloads

`query`, `getText`, `getAttributes`, and `getBoundingBox` payload:

```json
{
  "selector": "button.primary"
}
```

`click` payload:

```json
{
  "selector": "button.primary",
  "clickMode": "auto"
}
```

`clickMode` values:

- `auto` (default): prefer a trusted native click on the main frame and fall
  back to DOM `element.click()` when trusted delivery is not possible
- `trusted`: require a native trusted click; currently limited to the main
  frame and will auto-activate a background Browser page tab before clicking
- `dom`: always use DOM `element.click()`

`typeText` payload:

```json
{
  "selector": "input[name=email]",
  "text": "alice@example.com"
}
```

`waitForSelector` payload:

```json
{
  "selector": ".checkout-ready",
  "state": "present",
  "timeoutMS": "5000"
}
```

`getDOMSnapshot` payload:

```json
{
  "selector": "body",
  "maxDepth": "2",
  "includeText": "true"
}
```

Result notes:

- `query` returns the existing `BrowserDOMQueryResult` JSON shape
- `click` returns `BrowserDOMClickResult`
  with `trusted`, `transport`, and `fallbackUsed` metadata
- `typeText` returns `BrowserDOMTypeTextResult`
- `waitForSelector` returns the structured observer result produced by the page
  agent, including `found`, `timedOut`, `selector`, `state`, and `elapsedMS`
- `getText` returns `BrowserDOMTextResult`
- `getAttributes` returns `BrowserDOMAttributesResult`
- `getBoundingBox` returns `BrowserDOMBoundingBoxResult`
- `getDOMSnapshot` returns `BrowserDOMSnapshotResult`

## Error Semantics

Common structured error codes:

- `invalid_request`
  - malformed JSON
  - unsupported or missing payload keys
  - bad `pageID`
  - dead `browserTabID`
- `stale_document_revision`
  - the caller supplied `documentRevision`, but the target page has already
    navigated to a newer document
- `bridgeUnavailable`
  - the page bridge is not currently bound
- `pageNotFound`
  - the requested page is gone
- `internalFailure`
  - command dispatch reached the Browser control plane, but execution failed in
    a non-retryable way

Frame-specific notes:

- when `frameName` is missing or empty, the page main frame is used
- when `frameName` names a frame that no longer exists, the command currently
  fails with a structured Browser control error from the frame bridge
- callers should treat frame names as live page state and rediscover them with
  `listFrames` after navigation

### Event Subscription Lifecycle

- `subscribeEvents`
- `drainEvents`
- `unsubscribeEvents`

`subscribeEvents` payload:

```json
{
  "kindsJSON": "[\"consoleMessage\",\"navigationStateChanged\",\"networkRequestFinished\",\"popupRequest\",\"pageInspectionSnapshot\",\"download\",\"javaScriptDialog\",\"permissionRequest\",\"authenticationRequest\",\"certificateWarning\"]"
}
```

`drainEvents` payload:

```json
{
  "subscriptionID": "6B522A3E-0439-4E8F-8E90-55D6C9A4E94C",
  "limit": "50"
}
```

`unsubscribeEvents` payload:

```json
{
  "subscriptionID": "6B522A3E-0439-4E8F-8E90-55D6C9A4E94C"
}
```

## Event Kinds

The external event stream currently supports these `kind` values:

- `consoleMessage`
- `bridgeReady`
- `navigationStateChanged`
- `pageTitleChanged`
- `networkRequestFinished`
- `popupRequest`
- `pageInspectionSnapshot`
- `download`
- `javaScriptDialog`
- `permissionRequest`
- `authenticationRequest`
- `certificateWarning`

### Event Envelope

```json
{
  "id": "C68744A8-B9A6-4BEF-BB4B-4F8066E8F0BF",
  "version": "browser.tab.v1",
  "subscriptionID": "6B522A3E-0439-4E8F-8E90-55D6C9A4E94C",
  "browserTabID": "browser-tab-1",
  "kind": "networkRequestFinished",
  "payload": {
    "pageID": "5C11E4A8-5A79-4E89-B5DA-D0A66F6F3B58",
    "documentRevision": "3",
    "url": "https://example.com/favicon.ico",
    "method": "GET",
    "requestStatus": "success",
    "statusCode": "200",
    "statusText": "OK",
    "mimeType": "image/x-icon",
    "receivedContentLength": "363",
    "isMainFrame": "false",
    "frameName": ""
  },
  "createdAt": "2026-03-19T23:10:00Z"
}
```

### `pageInspectionSnapshot` Payload

`pageInspectionSnapshot` is synthesized from the existing DOM snapshot helper
when a subscribed page becomes ready or finishes a navigation.

Payload keys:

- `pageID`
- `documentRevision`
- `triggerKind`
- `frameName` (when available)
- `ok`
- `snapshotJSON` when `ok=true`
- `errorCode` / `errorMessage` when `ok=false`

`snapshotJSON` decodes into the same `BrowserDOMSnapshotResult` structure used
by the internal Browser control plane.

### `download` Payload

`download` is emitted for the Browser download lifecycle.

Payload keys:

- `pageID`
- `documentRevision`
- `phase` as `started`, `completed`, `canceled`, or `interrupted`
- `downloadID`
- `url`
- `suggestedName` when available
- `targetPath` when available
- `mimeType` when available
- `receivedBytes`
- `totalBytes`
- `percentComplete`
- `isComplete`
- `isCanceled`
- `isInterrupted`

### `cancelDownload`

Cancel a live Browser download that was previously observed through a `download`
event.

Payload keys:

- `downloadID`

Result keys:

- `downloadID`
- `accepted`
- `operation` as `cancelDownload`

The command acknowledges only that GhoDex accepted the cancellation request for
the live runtime handle. Callers should continue watching the `download` event
stream for the authoritative lifecycle update, which should eventually emit
`phase=canceled` for a successfully canceled transfer.

### `javaScriptDialog` Payload

`javaScriptDialog` is emitted when a page opens a JavaScript alert, confirm,
prompt, or before-unload dialog, and again after GhoDex resolves it through the
native dialog UI.

Payload keys:

- `pageID`
- `documentRevision`
- `requestID`
- `phase` as `requested` or `resolved`
- `dialogType` as `alert`, `confirm`, `prompt`, or `beforeUnload`
- `originURL` when available
- `messageText`
- `defaultPromptText` for prompt dialogs
- `isReload` for before-unload dialogs
- `accepted` on resolved events
- `userInput` on resolved prompt events

### `permissionRequest` Payload

`permissionRequest` is emitted for both media-device permission prompts and
generic browser permission prompts.

Payload keys:

- `pageID`
- `documentRevision`
- `requestID`
- `phase` as `requested` or `resolved`
- `permissionKind` as `media` or `generic`
- `originURL`
- `requestedPermissions`
- `requestedPermissionsLabel`
- `promptID` for generic permission prompts
- `result` on resolved events

### `authenticationRequest` Payload

`authenticationRequest` is emitted when a page or proxy challenges for HTTP
authentication, and again after GhoDex resolves the native auth dialog.

Payload keys:

- `pageID`
- `documentRevision`
- `requestID`
- `phase` as `requested` or `resolved`
- `originURL`
- `host`
- `port`
- `realm`
- `scheme`
- `isProxy`
- `accepted` on resolved events

### `certificateWarning` Payload

`certificateWarning` is emitted when TLS certificate validation fails and GhoDex
surfaces the native continue/cancel warning.

Payload keys:

- `pageID`
- `documentRevision`
- `requestID`
- `phase` as `requested` or `resolved`
- `requestURL`
- `errorCode`
- `accepted` on resolved events

## Runtime Prompt Resolve Commands

The external Browser control plane can resolve paused runtime prompts through
typed commands keyed by the event `requestID`.

### `resolveDialog`

Resolve a previously emitted `javaScriptDialog` event.

Payload keys:

- `requestID`
- `accepted` as `true` or `false`
- `userInput` for accepted prompt dialogs

### `resolvePermission`

Resolve a previously emitted `permissionRequest` event.

Payload keys:

- `requestID`
- `result` as `allow`, `deny`, or `dismiss`

### `resolveAuth`

Resolve a previously emitted `authenticationRequest` event.

Payload keys:

- `requestID`
- `accepted` as `true` or `false`
- `username` when `accepted=true`
- `password` when `accepted=true`

### `resolveCertificate`

Resolve a previously emitted `certificateWarning` event.

Payload keys:

- `requestID`
- `accepted` as `true` or `false`

All four commands return a result with:

- `requestID`
- `kind`
- `resolved`

### `popupRequest` Payload

`popupRequest` is emitted when Chromium asks GhoDex to route a `window.open`,
`target=_blank`, or popup/new-window navigation through the Browser control
plane.

Payload keys:

- `pageID`
- `documentRevision`
- `sourcePageID`
- `requestedURL`
- `disposition`
- `dispositionName`
- `userGesture`
- `routingTarget`
- `resultIsActive`
- `resultVisibilityState`
- `resultPageID` when the route resolved to a concrete Browser page
- `resultBrowserTabID` when the route resolved into a different Browser window

Known routing targets currently emitted:

- `currentPage`
- `pageTab`
- `existingPage`
- `browserWindow`
- `pageTabFallback`
- `popupWindowHost` for dedicated native popup-host windows that stay outside
  the first-class `browser.tab.v1` tab/page inventory

For `popupWindowHost`, `resultPageID` and `resultBrowserTabID` are currently
absent because the native popup host is observable but not yet exposed as a
first-class Browser tab target.

## CLI Examples

### 1. List live Browser tabs

```bash
ghodex +browser-control --transport=auto --request '{
  "id":"11111111-1111-1111-1111-111111111111",
  "version":"browser.tab.v1",
  "command":"listTabs",
  "payload":{}
}'
```

### 2. Open a new tab and capture the returned `browserTabID`

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"22222222-2222-2222-2222-222222222222",
  "version":"browser.tab.v1",
  "command":"newTab",
  "payload":{}
}'
```

### 3. Navigate that tab

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"33333333-3333-3333-3333-333333333333",
  "version":"browser.tab.v1",
  "command":"loadURL",
  "browserTabID":"browser-tab-1",
  "pageID":"E5F4C926-7F1C-466E-A6D9-3A6F6A2F6D4E",
  "payload":{"url":"https://example.com"}
}'
```

### 4. Discover the internal pages inside that Browser tab

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"44444444-4444-4444-4444-444444444444",
  "version":"browser.tab.v1",
  "command":"listPages",
  "browserTabID":"browser-tab-1",
  "payload":{}
}'
```

### 5. Activate one internal page inside that Browser tab

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"55555555-5555-5555-5555-555555555555",
  "version":"browser.tab.v1",
  "command":"activatePage",
  "browserTabID":"browser-tab-1",
  "payload":{"pageID":"E5F4C926-7F1C-466E-A6D9-3A6F6A2F6D4E"}
}'
```

### 6. Inspect the current debug-lane status

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"66666666-6666-6666-6666-666666666666",
  "version":"browser.tab.v1",
  "command":"getDebugStatus",
  "payload":{}
}'
```

### 7. Enumerate the frames inside one page

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"77777777-7777-7777-7777-777777777777",
  "version":"browser.tab.v1",
  "command":"listFrames",
  "browserTabID":"browser-tab-1",
  "pageID":"E5F4C926-7F1C-466E-A6D9-3A6F6A2F6D4E",
  "payload":{}
}'
```

### 8. Evaluate JavaScript inside a named frame

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"88888888-8888-8888-8888-888888888888",
  "version":"browser.tab.v1",
  "command":"evaluateJavaScript",
  "browserTabID":"browser-tab-1",
  "pageID":"E5F4C926-7F1C-466E-A6D9-3A6F6A2F6D4E",
  "frameName":"embedded-checkout",
  "payload":{"script":"JSON.stringify({ href: location.href, title: document.title })"}
}'
```

### 9. Run a DOM batch

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"99999999-9999-9999-9999-999999999999",
  "version":"browser.tab.v1",
  "command":"runDOMBatch",
  "browserTabID":"browser-tab-1",
  "pageID":"E5F4C926-7F1C-466E-A6D9-3A6F6A2F6D4E",
  "payload":{
    "commandsJSON":"[{\"id\":\"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA\",\"command\":\"query\",\"selector\":\"h1\"},{\"id\":\"BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB\",\"command\":\"getDOMSnapshot\",\"selector\":\"body\",\"maxDepth\":2,\"includeText\":true}]"
  }
}'
```

### 10. Query an element directly without `runDOMBatch`

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"AAAAAAAA-1111-1111-1111-111111111111",
  "version":"browser.tab.v1",
  "command":"query",
  "browserTabID":"browser-tab-1",
  "pageID":"E5F4C926-7F1C-466E-A6D9-3A6F6A2F6D4E",
  "payload":{"selector":"h1"}
}'
```

### 11. Wait for an element inside a named frame

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"BBBBBBBB-1111-1111-1111-111111111111",
  "version":"browser.tab.v1",
  "command":"waitForSelector",
  "browserTabID":"browser-tab-1",
  "pageID":"E5F4C926-7F1C-466E-A6D9-3A6F6A2F6D4E",
  "frameName":"embedded-checkout",
  "documentRevision":4,
  "payload":{"selector":".checkout-ready","state":"present","timeoutMS":"5000"}
}'
```

### 12. Inspect page-visible cookies in that tab

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
  "version":"browser.tab.v1",
  "command":"getCookies",
  "browserTabID":"browser-tab-1",
  "pageID":"E5F4C926-7F1C-466E-A6D9-3A6F6A2F6D4E",
  "payload":{
    "domain":"example.com"
  }
}'
```

### 13. Subscribe to passive events

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
  "version":"browser.tab.v1",
  "command":"subscribeEvents",
  "browserTabID":"browser-tab-1",
  "payload":{
    "kindsJSON":"[\"consoleMessage\",\"navigationStateChanged\",\"networkRequestFinished\",\"popupRequest\",\"pageInspectionSnapshot\",\"download\",\"javaScriptDialog\",\"permissionRequest\",\"authenticationRequest\",\"certificateWarning\"]"
  }
}'
```

### 14. Set a page-visible cookie in that tab

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC",
  "version":"browser.tab.v1",
  "command":"setCookie",
  "browserTabID":"browser-tab-1",
  "pageID":"E5F4C926-7F1C-466E-A6D9-3A6F6A2F6D4E",
  "payload":{
    "name":"session_id",
    "value":"abc123",
    "path":"/",
    "sameSite":"Lax"
  }
}'
```

### 15. Clear page-visible cookies in that tab

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD",
  "version":"browser.tab.v1",
  "command":"clearCookies",
  "browserTabID":"browser-tab-1",
  "pageID":"E5F4C926-7F1C-466E-A6D9-3A6F6A2F6D4E",
  "payload":{}
}'
```

### 16. Drain buffered events from that subscription

```bash
ghodex +browser-control --transport=ipc --request '{
  "id":"EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE",
  "version":"browser.tab.v1",
  "command":"drainEvents",
  "browserTabID":"browser-tab-1",
  "payload":{
    "subscriptionID":"6B522A3E-0439-4E8F-8E90-55D6C9A4E94C",
    "limit":"25"
  }
}'
```

## AppleScript Example

```applescript
set requestJSON to "{\"id\":\"77777777-7777-7777-7777-777777777777\",\"version\":\"browser.tab.v1\",\"command\":\"listTabs\",\"payload\":{}}"
tell application "GhoDex"
    set responseJSON to run browser command protocol requestJSON
end tell
```

## Client Guidance

- always generate a fresh UUID for each request
- treat `resultJSON` as a nested JSON string, not as a pre-decoded object
- `getCookies` currently reflects the page-visible `document.cookie` view, not
  the full Chromium cookie store
- `setCookie`, `deleteCookie`, and `clearCookies` also operate only on the
  page-visible `document.cookie` surface, so they do not touch HTTPOnly cookies
- subscribe once and drain incrementally instead of polling one-off inspection
  commands when you need passive page visibility
- keep draining long-lived IPC sessions; once unread response bytes on one
  connection exceed 1 MiB, GhoDex closes only that connection as backpressure
  protection
- prefer the IPC transport for long-lived local sessions; use AppleScript as a
  compatibility fallback
- treat unknown event kinds and extra payload keys as forward-compatible data,
  not as protocol violations

## Related Documents

- `browser-tab-control-architecture.md`
- `src/cli/browser_control.zig`
- `macos/Sources/Features/Browser/BrowserCommandProtocol.swift`
- `macos/Sources/Features/AppleScript/ScriptBrowserTab.swift`
