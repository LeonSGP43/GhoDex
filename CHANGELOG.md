# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### feat(config): sync GhoDex control-panel settings with config.ghodex

- What changed: Moved connection center, learning settings, and task queue
  persistence into managed `ghodex-*` entries in the main `config.ghodex`
  file; added reload-driven store/panel refresh; added regression coverage for
  managed-block load/save/reload behavior.
- Why: Settings that exist in both config and the control panel must have one
  app-owned source of truth and support two-way sync instead of diverging into
  a hidden sidecar JSON store.
- Impact: Users can configure these features directly in `config.ghodex`,
  reload the app config, and see matching values return to the panel. Panel
  edits now update the same main config file.
- Verification: `zig build`; `xcodebuild -project macos/Ghostty.xcodeproj
  -scheme Ghostty -only-testing:GhosttyTests/AITerminalManagerTests/
  storeLoadsConfigurationFromManagedGhoDexConfigBlock
  -only-testing:GhosttyTests/AITerminalManagerTests/
  storePersistsConfigurationIntoManagedGhoDexConfigBlock
  -only-testing:GhosttyTests/AITerminalManagerTests/
  storeReloadsPersistedConfigurationFromGhoDexConfig
  -only-testing:GhosttyTests/AITerminalManagerTests/
  storeUsesConfigDirectoryForHeartbeatInbox
  -only-testing:GhosttyTests/AITerminalManagerTests/storeSavesLearningSettings
  test`
- Files: `include/ghostty.h`,
  `macos/Sources/Features/AI Terminal Manager/AITerminalManagerStore.swift`,
  `macos/Sources/Features/SSH Connections/SSHConnectionsView.swift`,
  `macos/Sources/Ghostty/Ghostty.App.swift`,
  `macos/Sources/Ghostty/Ghostty.Config.swift`,
  `macos/Tests/AITerminalManager/AITerminalManagerTests.swift`,
  `src/cli/edit_config.zig`, `src/config/Config.zig`,
  `src/config/file_load.zig`

### docs(branding): start GhoDex naming pass and origin annotation

- What changed: Updated top-level branding in `README.md`, added upgrade highlights, added explicit `Project Origin` and `End Note`, renamed project wording in `AI_POLICY.md`, and added `ORIGIN.md` for provenance/thanks.
- Why: Establish GhoDex as an independent fork while preserving legal and historical attribution.
- Impact: User-facing docs now present `GhoDex` as the primary project name, with clear upstream lineage and unchanged MIT licensing notice.
- Verification: Checked updated docs for consistent fork naming, origin statement, and license reference (`README.md`, `AI_POLICY.md`, `ORIGIN.md`).
- Files: `README.md`, `AI_POLICY.md`, `ORIGIN.md`, `CHANGELOG.md`.

### docs(i18n): complete GhoDex display-name rollout across docs and UI text

- What changed: Rebranded remaining user-facing `Ghostty` display text to `GhoDex` across contributor/developer docs, spec docs, examples, translation catalogs (`po/*.po`, `po/*.pot`), macOS localized text tables, terminal window titles, and selected CLI/user messages.
- Why: Finish first-phase fork identity migration so user-visible copy is consistent with the `GhoDex` project name.
- Impact: UI labels, docs, and translated strings now present `GhoDex` consistently while technical/runtime identifiers (`ghostty`, `libghostty`, bundle IDs, target names) remain intact for compatibility.
- Verification: Searched for `Ghostty` in changed scopes and confirmed only expected technical/legal leftovers remain (e.g., module names, upstream attribution, compatibility identifiers).
- Files: `CONTRIBUTING.md`, `HACKING.md`, `PACKAGING.md`, `po/*.po`, `po/com.mitchellh.ghostty.pot`, `macos/Sources/Helpers/AppLocalization.swift`, `macos/Sources/Features/Terminal/Window Styles/*.xib`, `src/cli/*.zig`, `src/main_ghostty.zig`, `dist/windows/ghostty.rc` and related docs/tests.

## [0.1.0] - 2026-03-15

### feat(macos): AI terminal manager learning workflow and heartbeat queue

- What changed: Added learning settings/log persistence, workspace bootstrap, managed skill sync, and a heartbeat task queue with configurable interval/concurrency plus queue controls in settings UI.
- Why: Make repetitive local terminal orchestration and learning capture first-class app workflows instead of ad-hoc scripts.
- Impact: Users can configure learning capture, run queue tasks from UI/inbox, and track execution outcomes in-app.
- Verification: Existing macOS tests cover migration/persistence/queue execution paths (`macos/Tests/AITerminalManager/AITerminalManagerTests.swift`).
- Files: `macos/Sources/Features/AI Terminal Manager/AITerminalManagerModels.swift`, `macos/Sources/Features/AI Terminal Manager/AITerminalManagerStore.swift`, `macos/Sources/Features/SSH Connections/SSHConnectionsView.swift`, `macos/Tests/AITerminalManager/AITerminalManagerTests.swift`.

### test(update): language-agnostic localization assertions

- What changed: Replaced hardcoded English expectations with localization-aware assertions in updater/release-notes tests.
- Why: Prevent locale-dependent test failures in non-English environments.
- Impact: Update UI tests validate behavior across configured app languages.
- Verification: Test coverage updated in `ReleaseNotesTests.swift` and `UpdateViewModelTests.swift`.
- Files: `macos/Tests/Update/ReleaseNotesTests.swift`, `macos/Tests/Update/UpdateViewModelTests.swift`.

### chore(release): bootstrap standalone versioning metadata

- What changed: Added `VERSION` (`0.1.0`), initialized `CHANGELOG.md` with `Unreleased` and first release section, and added a versioning section in `README.md`.
- Why: Establish SemVer governance and satisfy repository pre-push version gate.
- Impact: Future releases have a canonical version source and changelog workflow.
- Verification: `VERSION` exists with SemVer value and changelog headings are present.
- Files: `VERSION`, `CHANGELOG.md`, `README.md`.
