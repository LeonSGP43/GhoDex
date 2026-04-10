# GhoDex Remote Sidecar

This directory is a sidecar Expo/React Native client shell forked from `happy/packages/happy-app`.

Purpose:

- reuse a polished mobile navigation and interaction shell
- keep the existing `wt-android-control-gateway` desktop gateway and auth model intact
- replace Happy-specific account, sync, encryption, and social features with GhoDex `ControlHarnessGateway` adapters

This is not wired to the GhoDex gateway yet. It is an adoption scaffold.

## Current Direction

- Keep desktop-side auth in `ControlHarnessAuth.swift`
- Keep desktop-side transport and policy in `ControlHarnessGateway.swift`
- Use this client only as a UI/runtime shell
- Replace Happy-specific data sources instead of porting the Happy backend

## Planned Replacements

Replace or heavily adapt these areas first:

1. `sources/auth/`
   - remove Happy account-linking and token derivation flows
   - replace with `gateway.pairing.begin` and `gateway.pairing.exchange`

2. `sources/sync/`
   - remove Happy server session/machine/artifact sync assumptions
   - replace with `snapshot`, buffered `events.stream.subscribe` / `events.stream.drain` / `events.stream.unsubscribe`, `read-terminal`, `send-text`, `run-command`

3. `sources/realtime/`
   - point live updates at the GhoDex gateway transport contract

4. `sources/app/`
   - rework routing so the first-run path is:
   - scan pairing QR
   - exchange pairing
   - snapshot terminal index
   - observe active terminal

## Config Notes

- `app.config.js` is intentionally renamed and de-branded for GhoDex
- Happy OTA, ownership, associated domains, and release metadata were removed from this fork scaffold
- `google-services.json` is still copied only as borrowed upstream scaffolding and should be replaced or removed before real Android release work

## First Validation Goal

The first meaningful milestone for this sidecar is not store-ready packaging. It is:

- boot the Expo client locally
- render a GhoDex-specific pairing screen
- exchange a pairing code against the local desktop gateway
- show snapshot-driven terminal inventory from the existing gateway
