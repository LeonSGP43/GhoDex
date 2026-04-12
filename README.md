# GhoDex

<p align="center">
  <img src="./images/readme/welcome-hero.jpg" alt="GhoDex Welcome Banner" width="960">
</p>

<p align="center">
  <strong>GhoDex OS</strong> combines Ghostty, Codex, and Harness into one terminal-native control surface for agent-driven development, browser automation, and programmable operator workflows.
</p>

<p align="center">
  <strong>Language</strong>:
  <a href="./README.md">English</a>
  ·
  <a href="./docs/README.zh-CN.md">Chinese</a>
</p>

<p align="center">
  <a href="#what-ghodex-is">What GhoDex Is</a>
  ·
  <a href="#product-highlights">Product Highlights</a>
  ·
  <a href="#project-status">Project Status</a>
  ·
  <a href="#roadmap">Roadmap</a>
  ·
  <a href="#installation">Installation</a>
  ·
  <a href="#operations">Operations</a>
  ·
  <a href="#development-and-contributing">Development & Contributing</a>
  ·
  <a href="#attribution">Attribution</a>
</p>

## What GhoDex Is

GhoDex starts with `Ghostty + Codex`. The broader product statement is `Ghostty + Codex + Harness = GhoDex OS`.

The project starts from Ghostty's native desktop terminal foundation and pushes it toward a Codex-style operator workstation: agent-driven execution, explicit control protocols, task orchestration, browser automation, knowledge capture, and remote collaboration paths in one product surface.

In practical terms, the Ghostty side gives GhoDex its terminal-native performance model and desktop runtime shell. The Codex side is what makes the product interesting: structured control, repeatable agent workflows, terminal-to-knowledge accumulation, programmable task execution, and a workstation designed to be operated by both humans and AI systems. The Harness side is what turns those ideas into an operable system surface: one explicit control authority that agents, operators, browser flows, runtime tasks, and remote clients can all target.

The goal is not only to run commands faster, but to make local development work programmable, inspectable, and easier to orchestrate across tabs, tasks, browser contexts, settings, and remote clients.

## Product Highlights

### 1. Codex-Centered Agent Workstation

- GhoDex is not positioned as "Ghostty with a few AI extras". The product direction is a Codex-style workstation built on top of Ghostty.
- Codex is the conceptual center for how the app is meant to be used: structured command execution, repeatable operator flows, context-aware task handling, and explicit automation authority instead of one-off shell prompts.
- The app architecture already reflects that direction through `ControlHarness`, runtime task/schedule flows, diagnostics, settings control, and workflow-oriented state.

Why this matters:
The strongest product story is not terminal rendering alone. It is that GhoDex tries to turn a native terminal app into a serious local execution environment for agentic software work.

### 2. AI-Native Terminal Operations

- AI Terminal Manager persists terminal-learning state, task/session state, remote session summaries, todo state, and managed skill repository metadata in one app-level store.
- Learning and workspace bootstrap flows are built into the product instead of being left as ad-hoc shell setup.
- Heartbeat execution is configurable with interval, concurrency, retention, and external inbox mutation controls.

Why this matters:
GhoDex is positioned as an operational workstation, not just a shell surface. It is designed to accumulate reusable knowledge and repeatable workflows over time.

### 3. Unified Control Harness Protocol

- `ControlHarness` is the single public automation authority for the current desktop app.
- The protocol already covers app lifecycle, workspace/tab/terminal control, runtime task/schedule control, todo operations, window/panel control, settings draft/apply flows, diagnostics, and browser automation.
- Legacy aliases are still accepted, but the product is converging on a stable namespaced command surface.

Why this matters:
This gives agents, operators, mobile clients, and future integrations one control plane instead of several fragmented entrypoints.

### 4. Browser Automation Inside the Desktop Runtime

- Browser automation is exposed through the same `ControlHarness` authority via `browser.*`.
- The current browser layer already supports tab/context/page/frame/DOM/cookie/event/prompt/download-oriented operations.
- Browser/CEF-enabled builds are now treated as a first-class runtime path with explicit runtime checks and failure gates.

Why this matters:
GhoDex can act as a local browser automation workstation while staying integrated with terminal sessions and desktop state, instead of forcing a separate browser toolchain.

### 5. Task, Runtime, and Scheduling Workflows

- Runtime commands already support session registration, heartbeats, lease release, task enqueue/claim/update/approve/cancel, and schedule enqueue/update/cancel.
- Todo workflows are not bolted on. They include snapshot/add/update/complete/assign/sync behaviors and document revision targeting.
- Settings and diagnostics are also exposed as controllable product surfaces, not just internal implementation details.

Why this matters:
This makes GhoDex usable as a local orchestration layer for repeatable operational work, not only interactive manual terminal use.

### 6. Built-In Developer Documentation Workflow

- Markdown files can be opened directly in-app with preview/source switching.
- The Markdown viewer supports live preview rendering, source editing, save flow, metadata summary, and font-size controls.
- This makes project docs, notes, and operational guides part of the same working environment as the terminal and browser.

Why this matters:
Documentation, operator notes, and command execution stay closer together, which is important for AI-assisted and multi-step workflows.

### 7. Desktop ↔ Mobile and Multi-Instance Routing

- GhoDex supports desktop-to-Android pairing flows based on QR/bootstrap configuration.
- The relay design already accounts for multiple desktop instances sharing one public endpoint through stable `desktop_id` routing.
- The owner-gateway design keeps one external entrypoint while still routing requests to the correct local desktop instance.

Why this matters:
Remote control and mobile access are treated as part of the product architecture, not as a temporary debug tunnel.

### 8. Workspace-Level Direction Beyond Tabs

- Workspace Map v1 already defines a top-level canvas mode that projects terminal and browser groups onto one controllable workspace view.
- The current design intentionally keeps runtime controllers as the source of truth and limits canvas commands to a safe v1 allowlist.

Why this matters:
GhoDex is moving toward a richer workspace control model while keeping architectural boundaries explicit and testable.

## Project Status

GhoDex is still an early-stage project. The architecture is already substantial, but the product is not claiming feature freeze or long-term API stability yet.

What is true today:

- The core desktop app, control protocol, browser integration, task/runtime model, and document workflow are real implemented surfaces.
- The project is actively maintained and still evolving quickly.
- Some areas are intentionally ahead of polish because the priority is building a programmable workstation foundation with real operator value.

What this means for teams and stakeholders:

- GhoDex is suitable to discuss as a serious prototype / early product with working foundations.
- It should still be presented honestly as an actively evolving system, not a finished platform.
- The strongest current story is: Ghostty as the native terminal base, Codex as the workflow and control philosophy, and GhoDex as the product that combines them into one programmable desktop workstation.

## Roadmap

The current medium-term direction is to keep shipping on top of the existing control-plane foundation rather than starting over.

### 1. Broaden the Unified Control Surface

- Continue moving external and out-of-repo clients onto the namespaced `ControlHarness` contract.
- Reduce remaining compatibility debt while keeping live clients stable.
- Strengthen verification lanes so protocol changes stay checkable.

### 2. Deepen AI Runtime and Task Orchestration

- Expand the runtime/session/task/schedule model into a more complete Codex-oriented workstation scheduler.
- Keep diagnostics, auditability, and operational visibility first-class as automation complexity grows.
- Improve the bridge between terminal learning, todo state, and queued execution.

### 3. Push the Browser + Desktop Convergence Further

- Keep browser automation inside the same public control authority as terminal/runtime flows.
- Continue hardening Browser/CEF packaging, runtime activation, and operator documentation.
- Improve the “one workstation, many controllable surfaces” model instead of splitting browser tooling out again.

### 4. Advance Remote and Mobile Collaboration

- Keep investing in desktop-to-mobile pairing reliability, routing isolation, and multi-instance gateway behavior.
- Make remote access behave more predictably across real multi-desktop environments.
- Preserve the rule that routing should be explicit, auditable, and instance-aware.

### 5. Evolve Workspace Map Carefully

- Grow Workspace Map from a safe projection layer toward richer workspace orchestration without breaking runtime ownership boundaries.
- Keep v2 features such as richer structural editing and more capable canvas interactions behind explicit contracts and gates.

### 6. Continue Product Maturity Work

- Improve release discipline, build reproducibility, and documentation quality.
- Keep `VERSION`, `CHANGELOG.md`, protocol docs, and acceptance evidence aligned with the actual shipped surface.
- Raise the quality bar without slowing down useful iteration.

## Why The Name

- `GhoDex = Ghostty + Codex`
- `GhoDex OS = Ghostty + Codex + Harness`

- `Ghostty` represents the native terminal base, desktop rendering, and high-performance terminal experience.
- `Codex` represents the agent workflow model, programmable control philosophy, execution-oriented UX, and the expectation that software work should be operable through explicit machine-usable interfaces.
- `Harness` represents the explicit machine-usable control plane that makes the workstation scriptable, inspectable, and safe to operate across tabs, runtime jobs, browser automation, settings, diagnostics, and remote entrypoints.
- `GhoDex` is the attempt to combine both into one product, while `GhoDex OS` is the stronger statement of intent: a terminal-first desktop environment that is also a real operating surface for AI-assisted development work.

## Installation

### 1. Quick Start (Release)

1. Open the releases page: <https://github.com/LeonSGP43/GhoDex/releases>
2. Download the release package for your platform.
3. Install and launch GhoDex.

### 2. Build From Source (Recommended on macOS)

#### Prerequisites

- Zig for the core build
- Xcode / `xcodebuild` for the macOS app build
- Nushell (optional) for the unified build script `macos/build.nu`

#### Clone the Repository

```bash
git clone https://github.com/LeonSGP43/GhoDex.git
cd GhoDex
```

#### Build the Core Only (Without Packaging the macOS App)

```bash
zig build -Demit-macos-app=false
```

#### Browser / CEF Default Build Notes

- `nu macos/build.nu` treats `--scheme GhoDex` as `CEF required` by default.
- The default runtime root is:
  `~/Library/Application Support/GhoDex/CEF/current`
- That directory must contain at least:
  - `Frameworks/Chromium Embedded Framework.framework`
  - `lib/Debug/libcef_dll_wrapper.a` or `lib/Release/libcef_dll_wrapper.a`
- The Browser host bridge calls SQLite APIs directly to manage runtime profile data, so a CEF-enabled build must also link against the system `libsqlite3`.
- `nu macos/build.nu` now injects `GHODEX_CEF_OTHER_LDFLAGS=-lsqlite3` automatically. If the current runtime is single-architecture, such as the common `macosarm64` codec-enabled lane, it also narrows the app build to the matching architecture so the CEF wrapper and app slice do not fail to link against each other.
- If the runtime is missing, `macos/build.nu` now fails immediately with an explicit error instead of silently producing an app where Browser stays in `unsupportedBuild`.
- If you intentionally want to build an app with Browser/CEF disabled, pass `--cef-mode disabled` explicitly.
- For Browser activation behavior and codec runtime supply details, see:
  [`browser-tab-runtime-activation.md`](./browser-tab-runtime-activation.md)
  and [`browser-tab-codec-runtime-playbook.md`](./browser-tab-codec-runtime-playbook.md)

#### Build the macOS App (Debug)

```bash
nu macos/build.nu --configuration Debug --action build
```

#### Build the macOS App (ReleaseLocal)

```bash
nu macos/build.nu --configuration ReleaseLocal --action build
```

#### Fallback Build Without Nushell

If you are building the main app with Browser/CEF enabled, prefer `nu macos/build.nu` above. It handles CEF runtime checks and build flag injection in one place.

The raw `xcodebuild` example below is better suited for low-level debugging. If you use it directly for a Browser-enabled app, you must provide the CEF-related flags yourself and keep the app architecture aligned with the active runtime architecture. For the current arm64-only runtime, the minimum setup looks like this:

```bash
GHODEX_CEF_ROOT="$HOME/Library/Application Support/GhoDex/CEF/current"

xcodebuild \
  -project macos/GhoDex.xcodeproj \
  -scheme GhoDex \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  EXCLUDED_ARCHS=x86_64 \
  GHODEX_CEF_ENABLED=1 \
  GHODEX_CEF_ROOT="$GHODEX_CEF_ROOT" \
  GHODEX_CEF_OTHER_LDFLAGS=-lsqlite3 \
  GHODEX_CEF_WRAPPER_LIB="$GHODEX_CEF_ROOT/lib/Debug/libcef_dll_wrapper.a" \
  build
```

## Operations

- Chinese operations guide: [`docs/OPERATIONS.zh-CN.md`](./docs/OPERATIONS.zh-CN.md)
- English operations guide: [`docs/OPERATIONS.en.md`](./docs/OPERATIONS.en.md)
- Control Harness protocol reference: [`docs/control-harness-protocol.md`](./docs/control-harness-protocol.md)
- Workspace Map v1 notes: [`docs/workspace-map-v1.md`](./docs/workspace-map-v1.md)
- Multi-instance relay routing notes: [`docs/ghodex-relay-desktop-routing.md`](./docs/ghodex-relay-desktop-routing.md)

## Recommended Configuration

To avoid accidentally clearing the entire current line in the shell, add this to `config.ghodex`:

```ini
keybind = ctrl+u=ignore
```

## Development and Contributing

- Development guide: [`HACKING.md`](./HACKING.md)
- Contribution guide: [`CONTRIBUTING.md`](./CONTRIBUTING.md)
- Version history: [`CHANGELOG.md`](./CHANGELOG.md)
- Current version: [`VERSION`](./VERSION)

## Attribution

GhoDex is built on top of [Ghostty](https://github.com/ghostty-org/ghostty), follows the upstream licensing and attribution requirements, and depends on the foundational work contributed by the Ghostty community.
