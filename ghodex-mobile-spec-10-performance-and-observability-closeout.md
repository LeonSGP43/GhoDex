# GhoDex Mobile SPEC-10: Performance And Observability Closeout

Created: 2026-03-26
Status: Completed

## Scope

This spec closes the initiative by adding the minimum structured measurements needed to prove the cleaned mobile app and upgraded connectivity path are observable.

It covers:

- launch and bootstrap timing on mobile
- Device and Workspace open latency tracking
- reconnect observability for live subscription recovery
- terminal update latency tracking on mobile
- verification that the GhoDex app shell bootstrap remains narrow and does not revive legacy Happy stacks

It does not cover:

- new dashboards, settings screens, or developer UI
- desktop transport metrics beyond the already existing gateway monitor
- protocol or renderer changes from `SPEC-08` / `SPEC-09`
- advanced retry tuning or sampling policy work

## Current State

Before this spec:

- desktop already has gateway performance monitoring and metrics tests
- mobile launch/bootstrap succeeds, but only exposes unstructured warnings on failure
- Workspace reconnect and terminal-refresh paths have behavior, but not structured counters or latencies
- route pruning and bootstrap cleanup already removed the old Happy product surface and runtime bootstrap path

## Target State

After this spec:

- mobile launch and bootstrap timings are measurable
- Device and Workspace open latencies are measurable
- reconnect attempts and reconnect recovery latency are observable
- terminal update latency is measurable on mobile
- the simplified GhoDex app shell bootstrap remains intentionally narrow and test-covered

## Source Of Truth

Desktop gateway metrics:

- source of truth: existing `ControlHarnessPerformanceMonitor`
- owner: desktop control-harness gateway

Mobile closeout metrics:

- source of truth: mobile GhoDex observability helper state
- owner: `happy-client/sources/ghodex/*`

Bootstrap behavior:

- source of truth: `bootstrapGhoDexAppShell`
- owner: `happy-client/sources/ghodex/appShell.ts`

## Measurement Contract

Required mobile measurements:

- launch start and launch-ready duration
- bootstrap duration and bootstrap failure count
- Device open duration
- Workspace open duration
- reconnect count, last scheduled delay, and last reconnect recovery latency
- terminal update count and last update latency

Required verification guard:

- app shell bootstrap must remain a session warmup only, without reintroducing legacy Happy auth or sync restore work

## Test Strategy

Before implementation:

- add observability unit tests for:
  - launch/bootstrap timing
  - screen-open timing
  - reconnect scheduling and recovery
  - terminal update latency
- add app-shell bootstrap tests proving bootstrap still only warms the stored device session

After implementation:

- run focused observability and app-shell tests
- rerun route-surface and transport tests already used in earlier specs
- rerun mobile typecheck

## Acceptance

`SPEC-10` is complete when all of the following are true:

- app launch timing is measurable on mobile
- Device and Workspace open timing is measurable on mobile
- reconnect behavior is observable through structured counters and timings
- terminal update latency is measurable on mobile
- existing desktop gateway metrics remain the desktop-side source of truth
- app shell bootstrap stays narrow and does not revive removed Happy background work

## Decision Trail

The narrowest coherent closeout is structured mobile measurements plus reuse of the existing desktop monitor.

Do not build a metrics UI.
Do not reopen transport or renderer work in the closeout spec.
Do not add a second observability system for desktop when the gateway already has one.

The safest path is:

1. add a small mobile observability helper with tests
2. instrument launch, Device, Workspace, reconnect, and terminal update paths
3. keep desktop metrics unchanged
4. prove the simplified app shell stays minimal

## Execution Result

Completed on 2026-03-26.

Implemented in this spec:

- mobile in-memory observability state in `happy-client/sources/ghodex/observability.ts`
- root launch/bootstrap instrumentation in `happy-client/sources/app/_layout.tsx`
- Device screen-open timing instrumentation in `happy-client/sources/app/(app)/gateway.tsx`
- Workspace open, reconnect, and terminal update instrumentation in `happy-client/sources/app/(app)/index.tsx`
- bootstrap narrowness coverage in `happy-client/sources/ghodex/appShell.spec.ts`

Verified constraints:

- launch-ready and bootstrap timings are recorded on mobile
- Device and Workspace open latency are recorded on the narrowed mobile surface
- live reconnect scheduling and recovery are recorded without adding a UI
- terminal read/apply latency is recorded by source without reopening renderer scope
- desktop observability ownership remains unchanged

## Verification

- `cd happy-client && yarn test sources/ghodex/observability.spec.ts sources/ghodex/appShell.spec.ts sources/ghodex/routes.spec.ts sources/ghodex/terminal/model.spec.ts sources/ghodex/terminalTransport.spec.ts sources/ghodex/gateway.spec.ts sources/ghodex/transport.spec.ts`
- `cd happy-client && yarn typecheck`
