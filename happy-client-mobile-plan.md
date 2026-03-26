# GhoDex Mobile Development Plan

Created: 2026-03-26
Worktree: `/Users/leongong/Desktop/LeonProjects/gho_workspace/wt-ghodex-mobile-pruning-connectivity-20260326`
Status: Completed

## Execution Update

Updated: 2026-03-26

Implemented in this worktree now:

- `SPEC-01` route and product-surface pruning:
  production Expo Router files were reduced to `index`, `gateway`, `pairing`, `settings`, `settings/language`, with `dev/*` left as the only gated non-product surface.
- `SPEC-02` runtime bootstrap simplification:
  root startup no longer boots the legacy Happy auth provider or `syncRestore`; it now hydrates only the GhoDex app shell and stored device session.
- `SPEC-03` settings and persistence cleanup:
  app settings remain theme/language/version only, and reserved GhoDex connection fields are explicitly stripped from the settings persistence path.
- `SPEC-04` branding and splash replacement:
  Expo config and active runtime metadata already use GhoDex Remote branding, and the remaining package/client identifiers were updated away from the old Happy client naming.
- `SPEC-05` device identity and 1:1 foundation:
  mobile stored-session schema now carries stable local device identity plus desktop identity / preferred desktop / transport metadata foundation, while preserving current LAN pairing behavior, and desktop control-harness auth now persists and exposes a stable authoritative desktop identity through pairing and token status responses.
- `SPEC-06` public-network encrypted connectivity:
  the repo now supports an opt-in public `wss://` gateway endpoint with AES-GCM application envelopes, pairing/token issue flows publish relay metadata and a per-binding shared secret, LAN mode remains unchanged, and mobile only upgrades to relay when the stored endpoint and shared secret are both valid.
- `SPEC-07` desktop device registry:
  mobile pairing now sends stable device identity hints, desktop auth persistence owns a device registry keyed by paired device id, the gateway can list and revoke devices from a local desktop command surface, and revoke now invalidates the target device's tokens plus closes active streams without affecting other devices.
- `SPEC-08` terminal transport upgrade:
  desktop delta reads now preserve complete `changed_rows` patches, mobile delta application is isolated into a testable transport helper with deterministic mixed update/delete merge behavior, and the workspace only requests delta when the current local buffer is safe to merge, otherwise falling back to snapshot.
- `SPEC-09` mobile terminal renderer:
  the workspace now keeps a parsed row model beside authoritative terminal text, safe delta reads update only touched rows, and the main terminal viewport renders through a row list instead of one giant ANSI text block.
- `SPEC-10` performance and observability closeout:
  mobile launch/bootstrap, Device/Workspace open, reconnect, and terminal-update paths now emit narrow in-memory structured measurements, while desktop keeps its existing gateway monitor as the desktop-side source of truth and app-shell bootstrap remains locked to stored-session warmup only.

Still pending after this execution update:

- none

## Goal

This plan defines the implementation path for turning `happy-client` into a dedicated GhoDex mobile remote client.

The work is split into explicit specs. Each spec includes:

- target state
- scope
- primary files and modules
- deliverables
- dependencies
- acceptance criteria

## Product Baseline

The current working baseline that must not regress during cleanup:

- mobile can pair with desktop from `Device`
- mobile stores the paired desktop session locally
- mobile home screen opens the remote workspace
- mobile can fetch snapshot, read terminal content, subscribe to live events, send commands, and show tab bell state
- mobile settings can still control theme and language

The preserved baseline currently lives mainly in:

- `happy-client/sources/app/(app)/index.tsx`
- `happy-client/sources/app/(app)/gateway.tsx`
- `happy-client/sources/app/(app)/settings/index.tsx`
- `happy-client/sources/app/(app)/settings/language.tsx`
- `happy-client/sources/ghodex/*`

## Architecture Rules

### Rule A: Single source of truth for app preferences

App preferences such as theme and language must continue to use one preferences store only.

Current preferred store:

- `happy-client/sources/sync/settings.ts`
- `happy-client/sources/sync/storage.ts`

### Rule B: Single source of truth for device connection state

Pairing state, gateway host and port, auth token, transport mode, preferred desktop, and future device identity must live only in:

- `happy-client/sources/ghodex/storage.ts`

They must not also be written into Happy settings or any hidden sidecar store.

### Rule C: Mobile product surface is GhoDex-only

Production mobile routes should converge to:

- Workspace
- Device
- Settings

Everything else is either deleted or gated behind explicit developer-only build flags.

### Rule D: Connectivity upgrades must not break LAN-first workflows

Public-network encrypted connectivity is a new layer on top of the current LAN path, not a replacement that breaks the existing local workflow.

### Rule E: Terminal improvements must not increase desktop complexity unnecessarily

Desktop should remain the authoritative source of terminal state and diffs.
Mobile can adopt a richer renderer, but desktop should not inherit a mobile-only rendering dependency chain.

## Delivery Order

Implementation order must follow this dependency chain:

1. `SPEC-00` baseline protection
2. `SPEC-01` route and product-surface pruning
3. `SPEC-02` runtime bootstrap simplification
4. `SPEC-03` settings and persistence cleanup
5. `SPEC-04` branding and splash replacement
6. `SPEC-05` device identity and 1:1 connection foundation
7. `SPEC-06` public-network encrypted connectivity
8. `SPEC-07` desktop device registry
9. `SPEC-08` terminal transport upgrade
10. `SPEC-09` mobile terminal renderer
11. `SPEC-10` performance and observability closeout

## SPEC-00 Baseline Protection

### Target State

Before large cleanup begins, the current working GhoDex flow is documented and can be reverified quickly after every major change.

### Scope

- capture the current intended GhoDex-only runtime flow
- define the smoke checks that every later spec must pass

### Primary Modules

- `happy-client/sources/app/(app)/index.tsx`
- `happy-client/sources/app/(app)/gateway.tsx`
- `happy-client/sources/app/(app)/settings/index.tsx`
- `happy-client/sources/ghodex/gateway.ts`
- `happy-client/sources/ghodex/storage.ts`

### Deliverables

- a baseline verification checklist in this plan
- optional small helper notes or scripted smoke steps if useful

### Dependencies

None

### Acceptance Criteria

- pairing from Device still succeeds end to end
- saved session is reused on next app launch
- workspace opens and loads a snapshot
- live updates or polling still refresh the selected terminal
- sending command text still works
- theme and language settings still apply

## SPEC-01 Route And Product-Surface Pruning

### Target State

The Expo Router tree only exposes GhoDex product routes in production.

### Scope

Keep:

- `index`
- `gateway`
- `pairing` only as alias if still needed
- `settings`
- `settings/language`

Remove or gate:

- `artifacts/*`
- `friends/*`
- `inbox/*`
- `machine/*`
- `new/*`
- `restore/*`
- `server.tsx`
- `session/*`
- `terminal/*`
- `user/*`
- extra `settings/*`
- `dev/*`

### Primary Modules

- `happy-client/sources/app/(app)/_layout.tsx`
- `happy-client/sources/app/(app)/*`
- `happy-client/sources/components/CommandPalette/*`
- any component still linking to removed routes

### Deliverables

- reduced route tree
- cleaned navigation entry points
- explicit debug gating decision for `dev/*`

### Dependencies

- `SPEC-00`

### Acceptance Criteria

- production route tree contains only GhoDex routes
- no visible navigation path can open old Happy screens
- search for removed route names in active imports and router pushes returns no production references
- workspace, Device, and Settings remain directly reachable

## SPEC-02 Runtime Bootstrap Simplification

### Target State

App startup no longer boots the old Happy auth and sync platform layers.

### Scope

Remove from root startup:

- `AuthProvider`
- `TokenStorage.getCredentials()`
- `syncRestore(credentials)`

Replace with:

- minimal app shell bootstrap for theme, language, and GhoDex device session hydration only

### Primary Modules

- `happy-client/sources/app/_layout.tsx`
- `happy-client/sources/auth/*`
- `happy-client/sources/sync/sync.ts`
- `happy-client/sources/sync/storage.ts`

### Deliverables

- simplified root layout
- explicit app-shell bootstrap contract
- removed runtime dependency on Happy account credentials

### Dependencies

- `SPEC-01`

### Acceptance Criteria

- root layout no longer imports or initializes `AuthProvider`
- root layout no longer imports or calls `TokenStorage`
- root layout no longer calls `syncRestore`
- cold launch remains successful
- theme and language still hydrate correctly
- workspace and Device still function after app relaunch

## SPEC-03 Settings And Persistence Cleanup

### Target State

Settings are reduced to GhoDex-relevant app preferences, while device connection state remains isolated in `ghodex/storage.ts`.

### Scope

Keep in app settings:

- theme
- language
- app version
- future GhoDex-specific app preferences only

Move or keep out of settings:

- gateway host and port
- auth token
- pairing state
- transport mode
- device identity

### Primary Modules

- `happy-client/sources/app/(app)/settings/index.tsx`
- `happy-client/sources/app/(app)/settings/language.tsx`
- `happy-client/sources/sync/settings.ts`
- `happy-client/sources/sync/storage.ts`
- `happy-client/sources/ghodex/storage.ts`

### Deliverables

- narrowed settings surface
- documented source-of-truth boundary
- removal of obsolete Happy settings keys from the visible UI

### Dependencies

- `SPEC-02`

### Acceptance Criteria

- theme and language remain round-trip persisted
- Device page remains the only place for connection management
- no connection fields are duplicated into app settings
- old Happy settings pages are unreachable
- language and theme still take effect without manual config edits

## SPEC-04 Branding And Splash Replacement

### Target State

The mobile app no longer exposes Happy branding in name, icon, splash, notification icon, scheme, or visible startup assets.

### Scope

Replace:

- app display name
- bundle and package presentation values where needed
- app icon set
- notification icon
- adaptive icon and monochrome icon
- splash asset images
- splash background colors

### Primary Modules

- `happy-client/app.config.js`
- `happy-client/sources/assets/images/icon*.png`
- `happy-client/sources/assets/images/splash-android-light.png`
- `happy-client/sources/assets/images/splash-android-dark.png`
- `happy-client/sources/app/_layout.tsx`

### Deliverables

- branded GhoDex asset set
- updated Expo config
- short replacement instructions for future asset refreshes

### Dependencies

- `SPEC-01`

### Acceptance Criteria

- app launcher icon shows GhoDex branding
- splash screen shows GhoDex branding and colors
- notification icon uses the intended asset
- no visible Happy name or logo appears during startup
- branding survives rebuild and reinstall

## SPEC-05 Device Identity And 1:1 Connection Foundation

### Target State

The connection model becomes device-centric and explicitly 1 phone to 1 primary desktop, instead of being only host plus token based.

### Scope

Introduce:

- mobile device identity
- desktop identity
- stored primary desktop binding
- stable session metadata for reconnect and future public transport

Do not yet require:

- relay transport
- public-network routing

### Primary Modules

- `happy-client/sources/ghodex/storage.ts`
- `happy-client/sources/ghodex/sessionState.ts`
- `happy-client/sources/ghodex/gateway.ts`
- `macos/Sources/Features/Control Harness/ControlHarnessCore.swift`

### Deliverables

- extended pairing/session schema
- desktop and mobile identity model
- updated storage contract

### Dependencies

- `SPEC-03`

### Acceptance Criteria

- a paired phone stores a stable device id locally
- desktop exposes a stable desktop identity
- pairing creates a device binding, not only a transient token write
- reconnect logic still works with the new schema
- existing LAN pairing remains backward-compatible or has a documented migration path

## SPEC-06 Public-Network Encrypted Connectivity

### Target State

GhoDex supports stable 1:1 connectivity beyond LAN through an authenticated relay or rendezvous layer, with end-to-end encrypted application payloads.

### Scope

Add:

- relay or rendezvous connectivity model
- outbound desktop tunnel support
- mobile attach flow
- end-to-end encrypted application frames
- heartbeat, resume, and reconnect semantics

Keep:

- direct LAN mode as the preferred low-latency path when available

### Primary Modules

- `happy-client/sources/ghodex/gateway.ts`
- `happy-client/sources/ghodex/types.ts`
- `happy-client/sources/ghodex/storage.ts`
- `macos/Sources/Features/Control Harness/ControlHarnessCore.swift`
- new relay-facing modules to be defined during implementation

### Deliverables

- transport design and envelope format
- session resume and heartbeat contract
- encrypted frame contract
- LAN and relay mode switching logic

### Dependencies

- `SPEC-05`

### Acceptance Criteria

- desktop and phone can connect when not on the same LAN
- relay does not require plaintext access to application payloads
- session can reconnect without re-pairing after temporary network loss
- mobile network changes do not permanently break the session
- direct LAN mode still works and is preferred when reachable

### Execution Notes

Completed in this worktree on 2026-03-26 as the smallest repo-supported public transport slice:

- desktop pairing and token rotation now publish an optional public `wss://` endpoint plus a per-binding `transport_shared_secret`
- mobile relay mode reuses the existing gateway protocol by wrapping requests, responses, and subscription events in AES-GCM application envelopes
- desktop decrypts `gateway.encrypted` requests and re-encrypts outbound envelopes when the authenticated token carries a shared secret
- direct LAN mode remains the default and safe fallback path

Verification evidence lives in:

- `ghodex-mobile-spec-06-public-network-encrypted-connectivity.md`
- focused mobile transport tests and focused control-harness tests recorded in that spec document

## SPEC-07 Desktop Device Registry

### Target State

Desktop can see, manage, and revoke connected mobile devices from an authoritative registry.

### Scope

Add desktop-side registry data for:

- device id
- display label
- trust state
- last seen
- current connection state
- transport type
- capability flags

### Primary Modules

- `macos/Sources/Features/Control Harness/ControlHarnessCore.swift`
- related desktop settings or UI modules to be defined during implementation

### Deliverables

- desktop registry model
- list and revoke actions
- link between registry and session authorization

### Dependencies

- `SPEC-05`
- `SPEC-06`

### Acceptance Criteria

- desktop can list connected or known devices
- desktop can show current and last-seen state
- desktop can revoke one device without affecting all devices
- revoked device loses access on next use or immediately if connected
- device list matches actual connection state without ghost entries

### Execution Notes

Completed in this worktree on 2026-03-26 as a desktop-authoritative registry slice:

- pairing begin now accepts mobile `device_id` and `device_label`
- the desktop auth store persists known-device rows next to token state and backfills older installs from existing token subjects
- the gateway exposes local-only `gateway.devices.list` and `gateway.devices.revoke` commands for management and test coverage
- device revoke is scoped to one paired identity and closes active streams for that device before returning

Verification evidence lives in:

- `ghodex-mobile-spec-07-desktop-device-registry.md`
- focused mobile gateway tests and focused control-harness registry tests recorded in that spec document

## SPEC-08 Terminal Transport Upgrade

### Target State

Terminal synchronization upgrades from raw text snapshots to structured frame or row diffs suitable for low-latency mobile rendering.

### Scope

Add support for:

- structured row or cell payloads
- changed row ranges
- cursor metadata
- prompt and semantic hints when available
- bounded replay and resume

Keep as fallback:

- current snapshot and raw text path

### Primary Modules

- `macos/Sources/Features/Control Harness/ControlHarnessCore.swift`
- `happy-client/sources/ghodex/types.ts`
- `happy-client/sources/ghodex/gateway.ts`

### Deliverables

- structured terminal payload schema
- frame or row diff transport contract
- fallback compatibility path

### Dependencies

- `SPEC-06`

### Acceptance Criteria

- terminal updates can be applied incrementally without full text rerender
- reconnect can resume from a recent frame or sequence
- raw text fallback still works for compatibility
- bell, title, cwd, and generation semantics remain correct

## SPEC-09 Mobile Terminal Renderer

### Target State

Mobile terminal rendering becomes readable, theme-aware, and performant, without relying on reparsing one giant ANSI string on every refresh.

### Scope

Replace the current main-path renderer with:

- row-based rendering
- theme-aware palette mapping
- selectable and readable text
- support for URLs, file paths, prompts, and future search and highlight features

Keep:

- `ansi.tsx` only as fallback or debug view if needed

### Primary Modules

- `happy-client/sources/app/(app)/index.tsx`
- `happy-client/sources/ghodex/ansi.tsx`
- new `happy-client/sources/ghodex/terminal/*` modules if introduced

### Deliverables

- new terminal renderer
- renderer state model
- compatibility fallback path

### Dependencies

- `SPEC-08`

### Acceptance Criteria

- terminal output is no longer rendered only as one large plain text block
- dark and light themes both preserve legibility
- long outputs scroll smoothly
- color, emphasis, and background regions remain correct
- copyable terminal text still matches the authoritative terminal content

## SPEC-10 Performance And Observability Closeout

### Target State

The cleaned app and upgraded connectivity path are measurable, observable, and verified against regressions.

### Scope

Add or tighten:

- launch-path measurement
- route-surface verification
- connection-state logging
- reconnect metrics
- terminal frame latency metrics

### Primary Modules

- `happy-client/sources/app/_layout.tsx`
- `happy-client/sources/app/(app)/index.tsx`
- `happy-client/sources/ghodex/*`
- desktop control harness metrics points

### Deliverables

- verification matrix
- key metrics or debug counters
- final performance checklist

### Dependencies

- `SPEC-01` through `SPEC-09`

### Acceptance Criteria

- app launch does not regress after cleanup
- Device and Workspace open without visible blocking stalls
- reconnect behavior is observable in logs or metrics
- terminal update latency is measurable
- no removed Happy feature continues background work after cleanup

## Acceptance Matrix

These checks define overall completion for the initiative:

### Product-Surface Acceptance

- production mobile UI contains only GhoDex routes and features
- no Happy branding remains in visible app flows
- no hidden old route can be reached from normal navigation

### State-Model Acceptance

- app preferences use one store
- device connection state uses one store
- no duplicate persistence path exists for the same setting

### Connectivity Acceptance

- LAN pairing and control still work
- one phone can keep a stable primary desktop binding
- public-network mode reconnects without requiring re-pairing
- encrypted public transport does not expose plaintext payloads to relay infrastructure

### Desktop-Visibility Acceptance

- desktop can list known devices
- desktop can revoke device access
- desktop view matches actual connection state

### Terminal Acceptance

- mobile terminal is readable in dark and light themes
- updates apply incrementally
- long output remains smooth
- raw text fidelity is preserved

### Performance Acceptance

- startup path is simpler than the old Happy-derived bootstrap
- Device and Settings open without the old route flash or blocking stalls
- terminal rendering and subscription updates do not make the app feel sluggish

## Non-Goals For This Initiative

- rebuilding the desktop terminal engine itself
- adding multi-desktop selection to the phone UX in the first pass
- adding a second independent settings system
- keeping old Happy product areas alive in hidden production routes

## Immediate Next Step

Start implementation with `SPEC-01` and `SPEC-02` together, because route pruning without bootstrap simplification will leave the old Happy platform still running in the background.
