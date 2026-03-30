# GhoDex Mobile SPEC-09: Mobile Terminal Renderer

Created: 2026-03-26
Status: Completed

## Scope

This spec replaces the main-path terminal renderer on mobile without changing the desktop transport contract.

It covers:

- a row-based terminal render model on mobile
- incremental row-model updates from safe `changed_rows` deltas
- a list-based terminal viewport instead of one giant text block
- theme-aware rendering that keeps default terminal colors readable in both app themes

It does not cover:

- terminal cursor rendering or blinking
- gesture features such as search, hyperlinks, or selection-specific UX
- transport metrics, latency counters, or performance instrumentation
- desktop protocol changes already handled by `SPEC-08`

## Current State

Before this spec:

- the workspace screen renders terminal output through one `ScrollView` that contains a large `Text` tree
- ANSI parsing exists, but only as a one-shot `renderAnsiText(content)` builder
- mobile holds authoritative terminal text in `terminalContent`, but not a reusable row model
- `SPEC-08` already guarantees safe delta usage for merge-safe local buffers

## Target State

After this spec:

- mobile stores a row-based render model beside the authoritative terminal text string
- snapshot reads rebuild the row model from full content
- safe delta reads update only the affected rows instead of reparsing the whole terminal buffer
- the workspace renders rows through a list viewport rather than one giant text node
- the fallback ANSI renderer remains available as a non-main-path helper

## Source Of Truth

Authoritative terminal text:

- source of truth: `terminalContent`
- owner: workspace screen state

Renderable row model:

- source of truth: derived mobile renderer cache from the authoritative text or safe delta patch
- owner: mobile terminal renderer helpers

Transport deltas:

- source of truth: `TerminalReadResult.changedRows`
- owner: `SPEC-08` transport contract

## Renderer Contract

### Stored mobile renderer state

Store:

- authoritative terminal text string
- parsed terminal rows

Each parsed row must preserve:

- exact raw line text
- ANSI-derived segments
- segment text order and style boundaries

### Derived render state

Derive at render time:

- list data from parsed rows
- per-segment text styles using theme colors for default foreground/background
- empty-state placeholder text when there is no terminal output

### Update rules

Snapshot path:

- rebuild parsed rows from `result.content`

Delta path:

- if `SPEC-08` marked the read as merge-safe, update only inserted and changed rows
- unchanged row objects should be preserved so the list does not churn unnecessarily
- any unsupported row patch still falls back to the snapshot path already enforced by the workspace

## Test Strategy

Before implementation:

- add terminal-model unit tests for:
  - ANSI row parsing fidelity
  - snapshot row-model construction
  - incremental row updates reparsing only touched rows
  - mixed update/delete row patches
  - unsupported patch rejection

After implementation:

- run focused mobile renderer and transport tests
- rerun gateway and transport tests from `SPEC-08`
- rerun mobile typecheck

## Acceptance

`SPEC-09` is complete when all of the following are true:

- terminal output is no longer rendered only as one large plain text block
- the main workspace path uses a row-based list renderer
- safe delta updates no longer require reparsing the entire terminal text buffer
- dark and light themes both keep default terminal content readable
- ANSI foreground, background, and emphasis regions remain correct
- copied row text still matches the authoritative terminal content for that row

## Execution Result

Completed in this worktree on 2026-03-26:

- added a pure terminal row-model helper that parses ANSI one line at a time and can apply `changed_rows` patches without reparsing untouched rows
- replaced the workspace main-path terminal viewport with a row-based list renderer so terminal output is no longer rendered as one giant text block
- kept the authoritative `terminalContent` string while storing parsed rows as a renderer cache beside it
- updated the workspace state flow so snapshot reads rebuild rows, while merge-safe delta reads update only touched rows
- retained `ansi.tsx` as a fallback/helper path by moving it onto the shared row parser instead of keeping a second ANSI parsing implementation

Verified with:

- `cd happy-client && yarn test sources/ghodex/terminal/model.spec.ts sources/ghodex/terminalTransport.spec.ts sources/ghodex/gateway.spec.ts sources/ghodex/transport.spec.ts`
- `cd happy-client && yarn typecheck`

Post-completion correction on 2026-03-27:

- root-caused the "all white text" field issue to desktop read output being plain-text-only in the control-harness sampling path, which stripped terminal styling before mobile parsing
- added a VT-preserving desktop read path (`ghostty_surface_read_text_vt`) and switched control-harness readable-surface sampling to that path
- normalized VT newline output from `\r\n` to `\n` before `read-terminal` framing so row indexes stay aligned with mobile row rendering
- added a ControlHarness regression test that locks ANSI row preservation across `snapshot` -> `delta` reads
- rebuilt `macos/GhoDexKit.xcframework` so the new VT read symbol is available to the macOS app target

Verified with:

- `cd happy-client && yarn test sources/ghodex/terminal/model.spec.ts sources/ghodex/terminalTransport.spec.ts sources/ghodex/gateway.spec.ts sources/ghodex/transport.spec.ts`
- `cd happy-client && yarn typecheck`
- `zig build -Demit-xcframework=true -Demit-macos-app=false`
- `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -derivedDataPath /tmp/ghodex-ansi-read-deriveddata -destination 'platform=macOS' -skip-testing:GhosttyUITests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build-for-testing`
- `xcodebuild -project macos/GhoDex.xcodeproj -scheme GhoDex -derivedDataPath /tmp/ghodex-ansi-read-deriveddata -destination 'platform=macOS' -skip-testing:GhosttyUITests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -only-testing:GhosttyTests/ControlHarnessTests/readTerminalDeltaPreservesCompleteChangedRowsWhenMaxLinesIsSmall -only-testing:GhosttyTests/ControlHarnessTests/readTerminalDeltaPreservesAnsiRowsForMobileRenderer test-without-building`

## Decision Trail

The narrowest coherent renderer upgrade is row-based parsing plus a list viewport.

Do not change the transport again in this spec.
Do not mix in latency counters or reconnect instrumentation from `SPEC-10`.
Do not overreach into cursor or selection UX before the basic row model is stable.

The safest path is:

1. extract a pure row-model helper with tests
2. switch the workspace to row-model state and list rendering
3. reuse `SPEC-08` deltas to update only touched rows
4. leave performance instrumentation and observability to `SPEC-10`
