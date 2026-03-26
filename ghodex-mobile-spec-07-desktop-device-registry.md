# GhoDex Mobile SPEC-07: Desktop Device Registry

Created: 2026-03-26
Status: Completed

## Scope

This spec adds the smallest desktop-authoritative device registry that fits on top of the current pairing and gateway stack:

- persist a desktop-owned registry keyed by mobile `device_id`
- register or refresh a device during pairing exchange
- update `last_seen_at` and last transport mode during authenticated token use
- expose local desktop management commands to list devices and revoke one device
- link device revoke to token revoke and active-session shutdown

This spec does not add:

- a desktop UI surface yet
- cross-desktop registry sync
- capability negotiation beyond an empty forward-compatible list
- transport or renderer changes from `SPEC-08` and `SPEC-09`

## Current State

Before this spec:

- mobile has a stable local `deviceId` and `deviceLabel`
- desktop issues tokens from pairing state, but does not persist a first-class device registry
- token/session authorization is scoped to an internal pairing subject, not to a durable device registry view
- desktop has no local management command to enumerate or revoke paired phones by `device_id`

## Target State

After this spec:

- `gateway.pairing.begin` can carry optional `device_id` and `device_label`
- desktop persists a registry row for each known device
- the registry row includes:
  - `device_id`
  - `display_label`
  - `trust_state`
  - `last_seen_at`
  - `current_connection_state`
  - `transport_mode`
  - `capability_flags`
- desktop can list known devices through a local-only gateway command
- desktop can revoke one device through a local-only gateway command
- revoking a device revokes its tokens and closes its active gateway streams

## Source Of Truth

Desktop registry:

- source of truth: desktop control-harness auth persistence
- owner: `ControlHarnessAuth`

Live connection state:

- source of truth: gateway session and active-stream tracking
- owner: `ControlHarnessGateway`

Mobile identity fields:

- source of truth: `happy-client/sources/ghodex/storage.ts`
- owner: mobile GhoDex session store

## Data Contract

### Pairing begin additions

Optional new request fields:

- `device_id`
- `device_label`

Compatibility rules:

- old mobile clients may omit both fields
- when omitted, desktop synthesizes a fallback registry identity from pairing state instead of failing the request

### Desktop registry entry

Persisted fields:

- `device_id`
- `display_label`
- `trust_state`
- `last_seen_at`
- `transport_mode`
- `capability_flags`

Derived field at read time:

- `current_connection_state`

Initial values:

- `trust_state = "trusted"` on successful pairing exchange
- `transport_mode = "lan"` on first local pairing unless later activity upgrades it
- `capability_flags = []` for now

### Local desktop management commands

List known devices:

- command: `gateway.devices.list`
- availability: local desktop origin only
- response shape:
  - `devices: DeviceRegistryEntry[]`

Revoke one device:

- command: `gateway.devices.revoke`
- availability: local desktop origin only
- request fields:
  - `device_id`
- effect:
  - mark the device as revoked in the registry
  - revoke all active tokens issued to that device
  - close active streams for that device identity

## Session / Registry Rules

Registry identity rules:

- when `device_id` is present, it becomes the durable device identity for registry and paired-session accounting
- when `device_id` is absent, desktop must still mint a fallback registry entry so pre-`SPEC-07` mobile clients remain pairable

Last-seen rules:

- pairing exchange records initial `last_seen_at`
- authenticated token use refreshes `last_seen_at`
- the most recent observed transport mode replaces the stored `transport_mode`

Connection-state rules:

- `current_connection_state = "connected"` when the gateway currently holds an active reserved session or stream for that device
- `current_connection_state = "idle"` otherwise

Revoke rules:

- revoke is device-scoped, not global
- revoking one device must not revoke unrelated paired devices
- a revoked device loses access on next request and should be disconnected immediately if it has an active live stream

## Test Strategy

Before implementation:

- add a mobile gateway unit test proving pairing begin sends `device_id` and `device_label`
- add focused desktop control-harness tests for:
  - registry listing after pairing
  - registry persistence across auth reload
  - device-scoped revoke without collateral damage
  - live connection state reporting and active-stream shutdown on revoke

After implementation:

- run focused mobile gateway and transport tests
- run focused control-harness registry tests
- rerun existing mobile typecheck and previously passing pairing/auth focused tests to avoid regression

## Execution Result

Completed in this worktree on 2026-03-26:

- mobile pairing begin now sends `device_id` and `device_label` from the persisted local GhoDex session so the desktop can bind a stable phone identity during pairing
- desktop control-harness auth persistence now carries a device registry alongside desktop identity and token state, keyed by the authoritative paired device identity and backfilled for older auth files that only contained token subjects
- registry rows now track `device_id`, `display_label`, `trust_state`, `last_seen_at`, `transport_mode`, and `capability_flags`, while live `current_connection_state` is derived from the gateway session registry at read time
- the gateway now exposes local-only `gateway.devices.list` and `gateway.devices.revoke` commands, and revoke is device-scoped: it revokes all tokens for that device identity and closes active gateway streams before returning
- pairing without explicit device identity remains backward-compatible because the desktop falls back to the pairing subject id and client label instead of rejecting older clients

Verified with:

- `cd happy-client && yarn test sources/ghodex/gateway.spec.ts sources/ghodex/transport.spec.ts`
- `cd happy-client && yarn typecheck`
- `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -derivedDataPath /tmp/ghodex-spec07-focused-deriveddata -destination 'platform=macOS' -skip-testing:GhosttyUITests -only-testing:GhosttyTests/ControlHarnessTests/authPairingExchangeReturnsStableDesktopIdentity -only-testing:GhosttyTests/ControlHarnessTests/authRestoresDesktopIdentityAcrossReload -only-testing:GhosttyTests/ControlHarnessTests/gatewayPairingLifecycleIssuesRotatesAndRevokesTokens -only-testing:GhosttyTests/ControlHarnessTests/gatewayPairingLifecyclePublishesRelayMetadataWhenPublicEndpointIsConfigured -only-testing:GhosttyTests/ControlHarnessTests/gatewayDeviceRegistryListsKnownDevicesAndPersistsAcrossReload -only-testing:GhosttyTests/ControlHarnessTests/gatewayDeviceRegistryRevokesOnlyTargetDeviceAndClosesActiveStreams test`

Environment note:

- this verification still pays the full macOS app build cost because the control-harness tests live in the main `GhosttyTests` target, but the focused target set above passed without needing the crash-prone full `ControlHarnessTests` batch

## Decision Trail

The smallest coherent registry slice is desktop-authoritative and local-first.

Do not add UI before the underlying registry and revoke semantics exist.
Do not make the phone the source of truth for trust state.
Do not create a second persistence silo when auth persistence already owns pairing and token issuance.

The safest path is:

1. extend pairing begin with mobile identity hints
2. persist a desktop-owned registry beside auth state
3. expose local-only list/revoke commands for management and testing
4. close active sessions on revoke so the registry actually controls authorization
