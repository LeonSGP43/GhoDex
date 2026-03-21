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
- Representative macOS acceptance run: not yet recorded in this worktree

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

- Status: pending
- Reason: instrumentation exists, but no representative desktop benchmark capture has been archived in this worktree yet
- Next step: run Scenarios A through C on a representative macOS build and paste the captured JSON snapshots plus CPU notes below

## Evidence Log Template

### Scenario A

- Duration:
- CPU:
- Typing lag observed:
- Metrics snapshot:

### Scenario B

- Duration:
- CPU:
- Render hitching observed:
- Metrics snapshot:

### Scenario C

- Duration:
- Network constraint:
- Local responsiveness preserved:
- Overflow/resync observed:
- Metrics snapshot:
