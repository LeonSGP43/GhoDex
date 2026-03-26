# GhoDex Mobile SPEC-08: Terminal Transport Upgrade

Created: 2026-03-26
Status: Completed

## Scope

This spec upgrades the terminal transport contract without changing the mobile renderer.

It covers:

- desktop frame-based terminal reads with explicit `frame_id` lineage
- row-delta transport that can be merged on mobile without re-reading the whole terminal buffer
- client-side safety rules for when delta is allowed vs when snapshot fallback is required
- reconnect and replay behavior using recent `frame_id` and subscription `last_sequence`

It does not cover:

- replacing the current ANSI text renderer
- row virtualization, theme-aware cell rendering, or cursor painting
- renderer-side incremental drawing optimizations
- URL/path/prompt presentation work planned for `SPEC-09`

## Current State

Before this spec:

- desktop already exposes `frame_id`, `parent_frame_id`, `delta_kind`, `delta_text`, `changed_rows`, `has_changes`, `next_cursor`, and `last_sequence`
- desktop already retains a bounded per-terminal frame history and can return reset-style delta content when the requested parent frame is missing
- mobile already requests `mode: "delta"` with `sinceFrameId` and falls back to snapshot when parent lineage is not usable
- mobile still renders terminal output as one ANSI-parsed text block inside the workspace screen

The remaining problem is transport correctness, not transport existence.
The current code path can still produce unsafe merges when the mobile side applies row deltas against a truncated or otherwise incompatible local buffer.

## Target State

After this spec:

- desktop returns a complete delta contract for merge-safe clients
- mobile only uses delta when its currently held terminal buffer is safe to merge
- mobile falls back to snapshot whenever the current buffer is truncated, lineage mismatches, or the delta payload is incomplete for a safe merge
- reconnect continues from the newest known `last_sequence`, while terminal reads continue from the newest safe `frame_id`
- raw text compatibility remains intact because snapshot reads still carry authoritative text content

## Source Of Truth

Desktop terminal state:

- source of truth: desktop control-harness readable surface + sampled store
- owner: `ControlHarnessCore` and `ControlHarnessTerminalReadStore`

Desktop frame lineage:

- source of truth: `ControlHarnessTerminalReadStore`
- owner: `macos/Sources/Features/Control Harness/ControlHarnessSupport.swift`

Mobile transport decisions:

- source of truth: mobile terminal read result and local merge eligibility rules
- owner: `happy-client/sources/ghodex/*` and `happy-client/sources/app/(app)/index.tsx`

Renderer output:

- source of truth: authoritative `content` string from the current terminal read result
- owner: current workspace screen until `SPEC-09`

## Transport Contract

### Desktop payload requirements

`read-terminal` must keep returning:

- `frame_id`
- `parent_frame_id`
- `mode`
- `content_kind`
- `content`
- `delta_kind`
- `delta_text`
- `changed_rows`
- `has_changes`
- `total_lines`
- `returned_lines`
- `truncated`
- `next_cursor`
- `last_sequence`

Contract rules:

- `frame_id` always identifies the captured desktop frame, not a mobile-local synthetic state
- `parent_frame_id` identifies the immediate previous desktop frame for the same terminal and scope
- `changed_rows` must be complete when the response claims mergeable row deltas
- when a requested base frame is unavailable, desktop may return reset-style content instead of pretending the row delta is mergeable

### Mobile merge rules

Mobile may request and apply delta only when:

- the current terminal id matches
- the current view has a usable `frameId`
- the current local buffer is not truncated
- the returned payload proves direct ancestry through `parent_frame_id` or a no-op same-frame response

Mobile must fall back to snapshot when:

- the current local buffer is truncated
- the parent frame does not match the requested base frame
- the delta claims changes but does not carry a safe row patch
- the row patch cannot be applied deterministically

### Resume rules

Subscription resume:

- continue from the highest observed `last_sequence`

Terminal read resume:

- continue from the last safe `frame_id`
- if that frame is no longer retained on desktop, accept reset or snapshot fallback instead of forcing an unsafe merge

## Safety Decisions

This spec deliberately keeps the mobile renderer unchanged.
That means transport safety must be enforced before the renderer sees any new content.

Two specific guardrails define this spec:

1. row deltas must be merged deterministically even when updates and deletions target adjacent lines
2. truncated snapshot windows are not valid merge bases for absolute desktop row indexes

If either guardrail is violated, the correct behavior is snapshot fallback, not a best-effort partial merge.

## Test Strategy

Before implementation:

- add focused desktop tests for:
  - delta round-trip across mixed update/delete rows
  - reset or fallback behavior when the requested base frame is no longer retained
  - delta responses preserving complete row patches instead of silently trimming them into an unsafe partial diff
- add focused mobile tests for:
  - deterministic row merge ordering across mixed update/delete operations
  - delta transport being disabled when the current local buffer is truncated
  - snapshot fallback when returned delta lineage is incompatible

After implementation:

- run focused mobile unit tests covering gateway + terminal transport helpers
- run focused desktop control-harness tests for delta contract behavior
- rerun mobile typecheck

## Acceptance

`SPEC-08` is complete when all of the following are true:

- terminal updates can be applied incrementally for merge-safe local buffers without forcing a full reread
- reconnect can resume from recent `frame_id` / `last_sequence` state and safely fall back when desktop no longer retains the requested base frame
- row-delta merges remain correct for mixed update/delete cases
- truncated local terminal buffers do not attempt unsafe delta merges
- raw text snapshot fallback still produces authoritative terminal content
- bell/title/cwd/generation semantics remain driven by the existing snapshot and event contracts

## Execution Result

Completed in this worktree on 2026-03-26:

- added a dedicated mobile transport helper module so delta-merge behavior is testable outside the workspace screen
- fixed row-delta application ordering so mixed `update` + `delete` patches merge deterministically instead of shifting later indexes
- tightened mobile delta eligibility so truncated local terminal buffers never attempt to merge absolute desktop row indexes
- kept snapshot fallback as the safety path when delta lineage mismatches or a changed delta response carries no safe row patch
- removed the desktop-side `maxLines` clamp from delta `changed_rows`, so the transport no longer advertises a mergeable row patch after silently trimming it into an unsafe partial diff

Verified with:

- `cd happy-client && yarn test sources/ghodex/terminalTransport.spec.ts sources/ghodex/gateway.spec.ts sources/ghodex/transport.spec.ts`
- `cd happy-client && yarn typecheck`
- `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -derivedDataPath /tmp/ghodex-spec08-focused-deriveddata -destination 'platform=macOS' -skip-testing:GhosttyUITests -only-testing:GhosttyTests/ControlHarnessTests/readTerminalDeltaPreservesCompleteChangedRowsWhenMaxLinesIsSmall -only-testing:GhosttyTests/ControlHarnessTests/readTerminalDeltaFallsBackToResetWhenSinceFrameWasEvicted test`

Environment note:

- the focused desktop verification still compiles the full macOS app and UI test host before running the requested ControlHarness tests, so this spec keeps the verification set intentionally narrow and isolated by `-derivedDataPath`

## Decision Trail

The narrowest coherent `SPEC-08` is a transport-correctness spec, not a renderer spec.

Do not mix renderer replacement into this step.
Do not trust a row delta unless the mobile side can prove it is merging against the right base frame.
Do not silently accept partial row diffs created by window budgets.

The safest path is:

1. document the exact transport boundary
2. add tests for merge safety and snapshot fallback
3. fix only the unsafe transport/merge cases
4. leave visual rendering upgrades to `SPEC-09`
