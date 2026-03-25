# GhoDex Operations Guide (English)

## Purpose

This guide covers daily usage, builds, tests, routine maintenance, and basic troubleshooting.

## Language Switch

- Chinese home: [`../README.md`](../README.md)
- English home: [`README.en.md`](./README.en.md)
- Chinese operations: [`OPERATIONS.zh-CN.md`](./OPERATIONS.zh-CN.md)

## 1. Daily Usage

### 1.1 Launch Paths

- Release package: install from GitHub Releases and launch directly.
- Source build: build first, then launch the generated app artifact.

### 1.2 Recommended Config

Add the following to `config.ghodex` to reduce accidental destructive input:

```ini
keybind = ctrl+u=ignore
```

## 2. Build Flow (macOS)

### 2.1 Prerequisites

- Zig
- Xcode / xcodebuild
- Nushell (recommended for the unified build script)

### 2.2 Clone and Enter Repo

```bash
git clone https://github.com/LeonSGP43/GhoDex.git
cd GhoDex
```

### 2.3 Build Core (core only)

```bash
zig build -Demit-macos-app=false
```

### 2.4 Build macOS App (Debug)

```bash
nu macos/build.nu --configuration Debug --action build
```

### 2.5 Build macOS App (ReleaseLocal)

```bash
nu macos/build.nu --configuration ReleaseLocal --action build
```

### 2.6 Fallback Without Nushell

```bash
xcodebuild \
  -project macos/GhoDex.xcodeproj \
  -scheme GhoDex \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build
```

## 3. Testing and Verification

### 3.1 Run Zig Tests (prefer targeted filters)

```bash
zig build test -Dtest-filter=<test_name>
```

### 3.2 Quick Diff Sanity Check

```bash
git diff --check
```

## 4. Common Maintenance Commands

### 4.1 Build Artifact Cleanup (dry run)

```bash
make prune-build-artifacts-dry-run
```

### 4.2 Build Artifact Cleanup (apply)

```bash
make prune-build-artifacts
```

### 4.3 Full Cleanup (use carefully)

```bash
make clean
```

## 5. Docs and Version Governance

- Version file: [`../VERSION`](../VERSION)
- Changelog: [`../CHANGELOG.md`](../CHANGELOG.md)
- Development guide: [`../HACKING.md`](../HACKING.md)
- Contributing guide: [`../CONTRIBUTING.md`](../CONTRIBUTING.md)

## 6. Troubleshooting

### 6.1 Build Failures

- Verify Zig and Xcode commands are available.
- Run `git diff --check` to catch formatting/conflict issues.
- Prefer `nu macos/build.nu` as the primary build entry.

### 6.2 Inconsistent Behavior Between ReleaseLocal and Debug

- Confirm stale artifacts are not being reused.
- Run `make clean` and rebuild with the intended configuration.

### 6.3 Mismatched Documentation Entry Points

- Chinese entry: [`../README.md`](../README.md)
- English entry: [`README.en.md`](./README.en.md)
