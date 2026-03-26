# GhoDex Mobile SPEC-05: Device Identity And 1:1 Binding Foundation

Created: 2026-03-26
Status: Completed

## Scope

This document covers only the `SPEC-05` foundation step:

- give the desktop a stable authoritative identity
- expose that identity through the existing pairing exchange path
- persist mobile device identity and desktop binding metadata locally
- keep the current LAN QR/manual pairing flow backward-compatible

This document does not introduce:

- relay transport
- public-network routing
- desktop-side multi-device registry UI
- device revoke UX

Those remain in later specs.

## Current State

Before this change set:

- desktop pairing issued only `auth_token`, `token_id`, `client`, and `scopes`
- mobile storage was effectively `host + port + pairingCode + authToken`
- clearing the mobile session deleted the entire saved record, including any future identity metadata

That model works for current LAN control, but it does not provide a durable 1:1 desktop binding contract.

## Target State

After `SPEC-05`:

- the desktop owns a stable `desktop_id`
- the desktop returns `desktop_id` and `desktop_label` during pairing exchange
- mobile owns a stable local `device_id`
- mobile stores `desktop_id`, `desktop_label`, `preferred_desktop_id`, and `transport_mode`
- clearing a paired desktop removes only the desktop binding and auth token, not the local phone identity

## Source Of Truth

Desktop authoritative identity:

- source of truth: desktop control-harness auth persistence
- owner: `ControlHarnessAuth`

Mobile authoritative identity and binding state:

- source of truth: `happy-client/sources/ghodex/storage.ts`
- owner: mobile GhoDex session store

App preferences:

- remain in `happy-client/sources/sync/settings.ts`
- must not duplicate any connection or identity fields from the GhoDex session store

## Data Contract

### Desktop pairing exchange result

The existing pairing exchange response is extended with optional fields:

- `desktop_id`
- `desktop_label`
- `preferred_desktop_id`
- `transport_mode`

Compatibility rule:

- old mobile clients ignore the new fields
- new mobile clients treat all four fields as optional and fall back to current LAN defaults when absent

### Mobile stored session

The mobile stored session now carries:

- `deviceId`
- `deviceLabel`
- `desktopId`
- `desktopLabel`
- `preferredDesktopId`
- `transportMode`

Compatibility rule:

- missing fields sanitize to safe defaults
- existing stored sessions migrate forward automatically on next load

## Desktop Identity Rules

`desktop_id` requirements:

- stable across app relaunches
- unique per desktop installation profile
- persisted durably, not recomputed from host/port

`desktop_label` requirements:

- human-readable
- stable enough for device UI
- safe to show in future desktop registry and mobile device pages

Preferred initial implementation:

- persist `desktop_id` inside control-harness auth state
- derive `desktop_label` from a normalized machine/app label at runtime, then include it in pairing/token responses

This keeps identity issuance close to token issuance and avoids creating a second persistence silo.

## Mobile Identity Rules

`device_id` requirements:

- generated once locally on first load
- stable across relaunches and pairing resets
- not cleared when the user removes a paired desktop

`device_label` requirements:

- simple local default such as `This phone`
- can be upgraded later without schema break

## Clearing / Reset Semantics

`clearStoredSession()` must:

- clear auth token
- clear pairing code
- clear desktop binding fields
- reset transport mode to `lan`
- preserve local `deviceId`
- preserve local `deviceLabel`

Reason:

- reset should mean "unlink this desktop" rather than "become a different phone"

## Test Strategy

Before implementation:

- extend control-harness auth tests to assert that pairing exchange now includes `desktop_id` and `desktop_label`
- assert that restored auth state keeps the same desktop identity
- assert that mobile storage clearing preserves local `deviceId`

After implementation:

- run targeted control-harness tests
- run mobile `typecheck`
- run existing mobile session/settings tests

## Execution Result

Completed in this worktree on 2026-03-26:

- desktop control-harness auth persistence now owns a stable `desktop_id` and `desktop_label`
- pairing exchange and token status responses now expose `desktop_id`, `desktop_label`, `preferred_desktop_id`, and `transport_mode`
- mobile session storage persists local phone identity separately from desktop binding metadata

Verified with:

- `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -derivedDataPath /tmp/ghodex-spec05-deriveddata -destination 'platform=macOS' -skip-testing:GhosttyUITests -only-testing:GhosttyTests/ControlHarnessTests/authPairingExchangeReturnsStableDesktopIdentity -only-testing:GhosttyTests/ControlHarnessTests/authRestoresDesktopIdentityAcrossReload test`
- `cd happy-client && yarn test sources/ghodex/routes.spec.ts sources/sync/settings.spec.ts`
- `cd happy-client && yarn typecheck`

Environment note:

- the default Xcode `DerivedData` path on this machine contained Finder metadata that broke codesign for `GhoDex.app`; the spec validation passed in a clean isolated `DerivedData` path, so the implementation is verified independently from that local cache issue

## Decision Trail

The first identity step should stay local-first and backward-compatible.

Do not block mobile cleanup on relay or registry work.
Do not invent a second desktop identity store outside control-harness auth just to satisfy the mobile contract.
Do not make mobile clearing destructive to the phone's own identity.

The safest path is:

1. desktop auth owns stable desktop identity
2. pairing exchange exposes that identity
3. mobile session persists it without changing current LAN semantics
4. later specs reuse the same fields for registry and relay work
