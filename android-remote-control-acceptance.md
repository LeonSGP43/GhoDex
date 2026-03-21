# Android Remote Control Acceptance

## Purpose

This file records how to gather and interpret the desktop-side acceptance evidence for the Android remote-control slice.

It is intentionally separate from the blueprint:

- the blueprint defines target behavior and milestones
- this file records how to capture evidence against the acceptance gates

## Current Status

Status date: `2026-03-21`

- Desktop feature slice through Milestone 3: implemented
- Acceptance instrumentation: available
- Representative macOS acceptance smoke run: recorded below
- Manual CPU / local typing-lag observation on a live desktop session: still pending

## Required Commands

Use a local desktop session and the loopback-only gateway.

Recommended flow:

1. Enable the gateway with loopback defaults and a known auth token.
2. Issue `gateway.metrics.reset` from a local client before each scenario.
3. Run one scenario at a time for a fixed observation window.
4. Issue `gateway.metrics` from a local client and archive the JSON payload.
5. Record any Activity Monitor or Instruments readings next to the JSON capture.

## Scenario Checklist

### Scenario A: One active observed terminal

Target:

- no perceptible local typing lag
- low bounded CPU while one remote observer is connected
- active terminal updates remain timely

Record:

- observation duration
- process CPU range
- `gateway.metrics` snapshot JSON
- whether local typing lag was perceptible

### Scenario B: Five observed terminals, one active

Target:

- background terminals remain on reduced cadence
- no visible local render hitching

Record:

- observation duration
- process CPU range
- `gateway.metrics` snapshot JSON
- whether sampler cadence reflects one active terminal and reduced background churn

### Scenario C: Slow or blocked mobile connection

Target:

- local desktop remains responsive
- gateway isolates the slow client
- overflow requires snapshot resync instead of unbounded queue growth

Record:

- how the client link was constrained
- `gateway.metrics` snapshot JSON
- whether overflow/resync was observed

## Local Gateway Commands

- `gateway.metrics`
  - returns the current rolling performance snapshot
- `gateway.metrics.reset`
  - clears the current rolling window and starts a fresh measurement interval

Important fields:

- `window_started_at`
- `window_age_ms`
- `sampler.tick`
- `sampler.capture`
- `sampler.last_target_count`
- `sampler.last_refreshed_count`
- `gateway.request`
- `gateway.total_requests`
- `gateway.open_streams`
- `gateway.stream_close_reasons`

## Representative Run Record

### Run 2026-03-21

- Status: in progress
- Scope: app-hosted automated smoke scenarios for `gateway.metrics.reset`, one active observed terminal, five observed terminals with background churn, and slow-client overflow/resync
- Verification:
  - `xcodebuild test -project macos/GhoDex.xcodeproj -scheme GhoDex -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:GhosttyTests/ControlHarnessTests/gatewayMetricsResetClearsRollingWindow -only-testing:GhosttyTests/ControlHarnessTests/acceptanceScenarioAActiveObservedTerminalArchivesMetrics -only-testing:GhosttyTests/ControlHarnessTests/acceptanceScenarioBFiveObservedTerminalsArchivesMetrics -only-testing:GhosttyTests/ControlHarnessTests/acceptanceScenarioCSlowClientOverflowArchivesMetrics -skip-testing:GhosttyUITests`
- Remaining gate: capture Activity Monitor or Instruments CPU data plus perceptible typing-lag notes from a live desktop session before closing Acceptance Metrics completely

## Evidence Log Template

### Scenario A

- Duration: automated smoke snapshot window (`window_age_ms = 0`) after a resettable metrics window
- CPU: not captured in this automated run
- Typing lag observed: not applicable in headless app-hosted smoke
- Metrics snapshot:

```json
{"generated_at":"2024-03-11T23:33:20.000Z","window_started_at":"2024-03-11T23:33:20.000Z","window_age_ms":0,"sampler":{"tick":{"count":1,"averageMs":3.4,"p95Ms":3.4,"maxMs":3.4},"capture":{"count":1,"averageMs":1.1,"p95Ms":1.1,"maxMs":1.1},"last_target_count":1,"last_refreshed_count":1,"last_tick_at":"2024-03-11T23:33:25.000Z","last_capture_scope":"visible","last_capture_activity_class":"observed","last_capture_at":"2024-03-11T23:33:26.000Z"},"gateway":{"request":{"count":2,"averageMs":3.4,"p95Ms":4.8,"maxMs":4.8},"stream_lifetime":{"count":0,"averageMs":0,"p95Ms":0,"maxMs":0},"total_requests":2,"open_streams":1,"total_streams_started":1,"total_streams_closed":0,"request_counts":{"events.subscribe":1,"read-terminal":1},"request_transport_counts":{"tcp":2},"stream_transport_counts":{"tcp":1},"stream_close_reasons":{}}}
```

### Scenario B

- Duration: automated smoke snapshot window (`window_age_ms = 0`) after a resettable metrics window
- CPU: not captured in this automated run
- Render hitching observed: not applicable in headless app-hosted smoke
- Metrics snapshot:

```json
{"generated_at":"2024-03-11T23:35:00.000Z","window_started_at":"2024-03-11T23:35:00.000Z","window_age_ms":0,"sampler":{"tick":{"count":1,"averageMs":6.2,"p95Ms":6.2,"maxMs":6.2},"capture":{"count":2,"averageMs":1.2,"p95Ms":1.5,"maxMs":1.5},"last_target_count":5,"last_refreshed_count":2,"last_tick_at":"2024-03-11T23:35:05.000Z","last_capture_scope":"screen","last_capture_activity_class":"background","last_capture_at":"2024-03-11T23:35:08.000Z"},"gateway":{"request":{"count":3,"averageMs":2.8333333333333335,"p95Ms":3.2,"maxMs":3.2},"stream_lifetime":{"count":0,"averageMs":0,"p95Ms":0,"maxMs":0},"total_requests":3,"open_streams":1,"total_streams_started":1,"total_streams_closed":0,"request_counts":{"events.subscribe":1,"read-terminal":2},"request_transport_counts":{"tcp":3},"stream_transport_counts":{"tcp":1},"stream_close_reasons":{}}}
```

### Scenario C

- Duration: automated smoke snapshot window (`window_age_ms = 0`) after a resettable metrics window
- Network constraint: simulated slow client with a tiny per-client buffer (`maxBufferedEvents = 2`, `maxBufferedBytes = 64`)
- Local responsiveness preserved: yes, verified by isolated overflow on the slow session while the gateway metrics surface remained queryable
- Overflow/resync observed: yes, `ControlHarnessGatewayClientSession.drain()` reported `requiresSnapshotResync = true` and the metrics stream-close reasons recorded `overflow_resync = 1`
- Metrics snapshot:

```json
{"generated_at":"2024-03-11T23:36:40.000Z","window_started_at":"2024-03-11T23:36:40.000Z","window_age_ms":0,"sampler":{"tick":{"count":1,"averageMs":3.9,"p95Ms":3.9,"maxMs":3.9},"capture":{"count":0,"averageMs":0,"p95Ms":0,"maxMs":0},"last_target_count":1,"last_refreshed_count":1,"last_tick_at":"2024-03-11T23:36:45.000Z","last_capture_scope":null,"last_capture_activity_class":null,"last_capture_at":null},"gateway":{"request":{"count":1,"averageMs":2.1,"p95Ms":2.1,"maxMs":2.1},"stream_lifetime":{"count":1,"averageMs":42.0,"p95Ms":42.0,"maxMs":42.0},"total_requests":1,"open_streams":0,"total_streams_started":1,"total_streams_closed":1,"request_counts":{"events.subscribe":1},"request_transport_counts":{"tcp":1},"stream_transport_counts":{"tcp":1},"stream_close_reasons":{"overflow_resync":1}}}
```
