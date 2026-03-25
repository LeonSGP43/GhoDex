# Mobile Gateway Optimization Plan

Last Updated: 2026-03-24

## Goal

Record the current GhoDex desktop-to-mobile gateway design, the known security and performance limits, and the future optimization targets for a production-grade remote control path.

## Current Architecture

### Connection Flow

1. Desktop GhoDex starts a local gateway listener on a configurable host and port.
2. Mobile scans a desktop QR code that contains `host`, `port`, and a short-lived `pairing_code`.
3. Mobile exchanges the `pairing_code` for an `auth_token`.
4. Mobile uses that token to call:
   - `snapshot`
   - `read-terminal`
   - `run-command`
   - `send-text`
5. Terminal reads currently use `snapshot + delta polling`, and write operations use a short settle loop to wait for the next visible result.

### Current Transport Characteristics

- Transport is `ws://host:port`, not `wss://`.
- The desktop gateway terminates the connection and sees plaintext terminal content and commands.
- Mobile session state is stored locally with `expo-secure-store`.
- Gateway auth supports:
  - short-lived pairing code
  - scoped token (`observe`, `mutate`)
  - token TTL
  - token revoke / rotate
  - rate limits
  - concurrent session limits

## Current Security Verdict

### What It Is

- Token-authenticated remote gateway for:
  - USB debugging with `adb reverse`
  - trusted LAN usage

### What It Is Not

- Not TLS-encrypted in transit
- Not end-to-end encrypted
- Not safe to expose directly to the public internet as-is

## Why It Is Not End-to-End Encrypted

This design is not E2EE because the desktop gateway is an active protocol endpoint:

- it accepts the socket connection
- it validates the token
- it reads terminal output
- it injects terminal input
- it returns terminal snapshots and deltas

That means the gateway process can see plaintext content. In a real E2EE design, the relay layer would not be able to read terminal payloads.

## Main Risks In The Current Design

### Transport Risk

- `ws://` means traffic is plaintext on the network path.
- Any untrusted LAN or routed network is unsafe.

### Pairing Risk

- `pairing.exchange` is reachable remotely if the caller has the pairing code.
- If the QR payload leaks, an attacker can try to exchange it before expiry.

### Token Risk

- The auth model is bearer-token based.
- A stolen token can be replayed until expiry or revocation.

### Public Exposure Risk

- No TLS
- No certificate pinning
- No device-bound cryptographic proof during pairing
- No relay trust boundary
- No hardened public-facing authentication layer

### Performance Risk

- The mobile client opens a fresh WebSocket per request instead of reusing one long-lived session.
- Terminal freshness is driven by polling, not true push streaming.
- This is acceptable on USB / LAN, but not ideal on higher-latency networks.

## Current Performance Verdict

### Good Enough For

- local USB debugging
- trusted LAN
- MVP validation
- manual terminal control

### Not Good Enough Yet For

- internet-scale remote access
- low-latency realtime remote shell UX
- high-frequency multi-terminal control

## Target Product Direction

The desired future state should be:

- secure by default
- no environment variable ceremony for everyday use
- single gateway per desktop instance group
- desktop app owns gateway settings directly in UI
- mobile app can pair and reconnect reliably
- transport remains fast enough for interactive terminal control

## Recommended Optimization Roadmap

### Phase 1: Harden The Existing LAN/USB Design

Goals:

- keep current desktop-owned gateway model
- improve safety without changing overall architecture

Tasks:

- add explicit gateway enable/disable state in desktop settings
- make pairing UX reliable and auditable
- reduce token lifetime for sensitive scopes if needed
- expose token revoke and session management in UI
- tighten logs and error reporting
- keep one active gateway port owner and surface passive/failure state clearly

Acceptance:

- desktop and mobile reconnect reliably
- token lifecycle is visible and manageable
- users can understand whether the gateway is active, passive, or failed

### Phase 2: Replace Polling With Persistent Session Transport

Goals:

- improve interactivity
- reduce connection setup overhead

Tasks:

- move from per-request WebSocket usage to one persistent connection
- multiplex snapshot, delta, command ack, and terminal events over one session
- support server-push updates instead of frequent polling
- keep read-after-write ordering guarantees

Acceptance:

- lower end-to-end latency
- fewer transient timeout issues
- stable realtime terminal updates on normal networks

### Phase 3: Add Real Transport Security

Goals:

- secure traffic in transit
- prepare for non-LAN usage

Tasks:

- support `wss://`
- terminate TLS safely
- add certificate trust model
- consider certificate pinning on mobile
- define local-dev vs production trust behavior

Acceptance:

- no plaintext terminal traffic on the network
- mobile rejects untrusted endpoints by default

### Phase 4: Strengthen Pairing And Identity

Goals:

- make pairing resistant to QR leakage and replay

Tasks:

- bind pairing to a device keypair generated on mobile
- add challenge-response during exchange
- issue device-bound session credentials instead of raw bearer-only trust
- consider one-time QR claims with nonce replay protection

Acceptance:

- stolen QR payload alone is not enough for durable takeover
- replay attempts are detectable and rejectable

### Phase 5: Public Network / Internet Access

Two viable directions exist:

#### Option A: Private Overlay First

Use Tailscale / WireGuard / similar private networking.

Pros:

- fastest path to practical remote access
- lower implementation risk
- reuses current gateway model

Cons:

- depends on private network tooling
- still not full internet-native product architecture

#### Option B: Internet-Native Gateway / Relay

Build a production relay and remote session architecture.

Pros:

- product-grade public access model
- better long-term extensibility

Cons:

- much more engineering work
- security design becomes significantly harder

Recommendation:

- choose Option A first for real-world usage
- only build Option B after transport security and identity hardening are complete

## Security Positioning For Now

Current safe statement:

"Safe enough for USB debugging and trusted LAN usage, but not suitable for direct public internet exposure."

Current unsafe statement:

"This is end-to-end encrypted and ready for公网 remote control."

That statement would be incorrect with the current codebase.

## Performance Positioning For Now

Current safe statement:

"Interactive enough for MVP use on USB and LAN, but still based on polling and repeated request connections."

Target future statement:

"Persistent encrypted session with server-push updates and low-latency terminal interaction."

## Future Acceptance Criteria

The design can be considered "production-grade remote access" only when all of the following are true:

- encrypted transport by default
- no plaintext network path
- pairing is resistant to replay and QR leakage
- device identity is cryptographically bound
- session revoke / rotate / expiry are manageable
- persistent low-latency transport is in place
- failure modes are visible in desktop and mobile UI
- public exposure model has a clear trust boundary

## Short Conclusion

The current implementation is a good MVP remote gateway for desktop-controlled mobile pairing on USB and trusted LAN.

It is not end-to-end encrypted.
It is not yet suitable for direct public internet exposure.
The next major upgrades should be:

1. persistent session transport
2. TLS / `wss`
3. device-bound pairing and stronger auth
4. private-overlay or relay strategy for cross-network access
