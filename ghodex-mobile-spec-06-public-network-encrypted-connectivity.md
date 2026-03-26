# GhoDex Mobile SPEC-06: Public-Network Encrypted Connectivity

Created: 2026-03-26
Status: Completed

## Scope

This spec implements the smallest public-network slice that fits the current repo:

- support a stored public `wss://` endpoint for an already-paired desktop
- add an application-layer encrypted gateway frame wrapper for public transport
- keep existing LAN `ws://host:port` behavior unchanged
- reuse existing token auth, `since_sequence`, and `frame_id` resume semantics

This spec does not add:

- a new hosted relay service inside this repo
- NAT traversal automation
- desktop device registry UI
- terminal transport schema changes

## Current State

Before this spec:

- mobile only connects to `ws://host:port`
- public transport mode exists in storage only as a placeholder
- gateway requests and subscription events are plaintext JSON frames
- reconnect already reuses `since_sequence` and `since_frame_id`, but only on the current transport

## Target State

After this spec:

- pairing exchange can optionally return a durable `public_endpoint`
- pairing exchange can optionally return a per-binding `transport_shared_secret`
- mobile stores those values alongside the current desktop binding
- mobile uses `wss://` public transport when `transportMode === 'relay'`
- public transport frames wrap the existing gateway request/response/event JSON inside an encrypted payload
- desktop decrypts `gateway.encrypted` requests, handles the inner request normally, and encrypts the response/event payloads back to mobile

## Source Of Truth

Desktop public transport metadata:

- source of truth: control-harness auth persistence plus gateway app settings
- owner: `ControlHarnessAuth` and `ControlHarnessGatewayAppSettings`

Mobile public transport metadata:

- source of truth: `happy-client/sources/ghodex/storage.ts`
- owner: mobile GhoDex session store

## Data Contract

### Pairing exchange additions

Optional new fields:

- `public_endpoint`
- `transport_shared_secret`

Compatibility rules:

- old mobile clients ignore the new fields
- new mobile clients stay on LAN mode if either field is missing

### Mobile stored session additions

New persisted fields:

- `publicEndpoint`
- `transportSharedSecret`

Reset rules:

- clearing a paired desktop must clear both fields
- local `deviceId` and `deviceLabel` remain preserved

### Encrypted request wrapper

Public-mode gateway requests are wrapped as:

- outer command: `gateway.encrypted`
- outer auth token: existing `auth_token`
- outer payload: `encrypted_payload` as base64url
- outer transport marker: `transport_mode = "relay"`

The encrypted inner payload is the original JSON request without modification to command semantics.

### Encrypted response / event wrapper

Public-mode responses and subscription events are wrapped as:

- `transport_mode = "relay"`
- `encrypted_payload` as base64url

The decrypted payload is the original `GatewayEnvelope` / `ControlHarnessResponse` JSON.

## Encryption Model

Initial public-network slice:

- pairing happens on the existing trusted LAN path
- desktop generates a random 32-byte `transport_shared_secret`
- mobile stores that secret locally with the paired desktop binding
- public transport encrypts the application payload with AES-GCM using that shared secret

Reason:

- the repo already has working mobile AES helpers and base64 helpers
- this avoids adding a second asymmetric handshake system before public transport works at all
- later relay/rendezvous work can still reuse the same encrypted frame contract

## URL Resolution Rules

LAN mode:

- use `ws://host:port`

Public mode:

- use stored `publicEndpoint`
- require `wss://`
- if `publicEndpoint` is invalid or missing, fall back to LAN mode instead of half-opening a broken relay state

## Test Strategy

Before implementation:

- add mobile unit tests for URL resolution and encrypted frame wrapping/unwrapping
- add desktop unit tests for encrypted request/envelope encode-decode round trips
- extend session-storage tests for `publicEndpoint` and `transportSharedSecret` persistence/reset behavior if needed during implementation

After implementation:

- run focused mobile transport tests
- run focused control-harness tests
- rerun current mobile route/settings tests and typecheck

## Execution Result

Completed in this worktree on 2026-03-26:

- mobile transport resolution now prefers a stored `wss://` public endpoint only when `transportMode === 'relay'`, the endpoint is valid, and a non-empty `transportSharedSecret` is present
- mobile request/response and subscription flows now wrap public-mode gateway payloads in `gateway.encrypted` AES-GCM envelopes while leaving LAN `ws://host:port` behavior unchanged
- pairing exchange and token rotation now propagate `public_endpoint`, `transport_shared_secret`, and relay transport metadata into the mobile session store without breaking older LAN-only responses
- desktop control-harness auth now issues and persists a per-token `transport_shared_secret`, migrates older persisted tokens forward by synthesizing the missing secret during decode, and uses that secret to decrypt inbound relay requests plus encrypt outbound responses/events
- desktop gateway configuration now accepts an optional `GHODEX_CONTROL_HARNESS_GATEWAY_PUBLIC_ENDPOINT` / `publicEndpoint` and publishes relay metadata during pairing/token issue flows only when that endpoint resolves to a valid `wss://` URL

Verified with:

- `cd happy-client && yarn test sources/ghodex/routes.spec.ts sources/sync/settings.spec.ts sources/ghodex/transport.spec.ts`
- `cd happy-client && yarn typecheck`
- `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -derivedDataPath /tmp/ghodex-spec06-focused-deriveddata -destination 'platform=macOS' -skip-testing:GhosttyUITests -only-testing:GhosttyTests/ControlHarnessTests/authExpiresPairingCodesAndPersistsIssuedTokens -only-testing:GhosttyTests/ControlHarnessTests/authPairingExchangeReturnsStableDesktopIdentity -only-testing:GhosttyTests/ControlHarnessTests/authRestoresDesktopIdentityAcrossReload -only-testing:GhosttyTests/ControlHarnessTests/gatewaySecureChannelRoundTripsEncryptedRequest -only-testing:GhosttyTests/ControlHarnessTests/gatewaySecureChannelRoundTripsEncryptedEnvelope -only-testing:GhosttyTests/ControlHarnessTests/gatewayPairingLifecycleIssuesRotatesAndRevokesTokens -only-testing:GhosttyTests/ControlHarnessTests/gatewayPairingLifecyclePublishesRelayMetadataWhenPublicEndpointIsConfigured test`

Environment note:

- the full `ControlHarnessTests` batch in this repo still hits an unrelated app-host failure outside the control-harness path, so `SPEC-06` acceptance was closed with focused gateway/auth coverage in an isolated `DerivedData` path

## Decision Trail

The repo does not currently contain a hosted relay service, so the first coherent public-network step is:

1. keep the existing desktop gateway commands and resume semantics
2. add a public endpoint descriptor rather than inventing a second connection protocol
3. encrypt the application payloads so public transport is not plaintext even when the endpoint is externally exposed
4. defer registry and richer tunnel automation to later specs

This keeps `SPEC-06` compatible with later `SPEC-07` and `SPEC-08` work instead of forcing another transport reset.
