# Browser Codec Runtime Playbook

## Purpose

This playbook records the repo-owned path for producing and validating a
codec-enabled CEF runtime after the Browser codebase was already made
descriptor-driven.

Read `browser-tab-runtime-activation.md` first if the Browser tab currently
shows `compiled without managed Chromium runtime support`. That state means the
app binary itself was built without CEF host support, which must be fixed
before codec/runtime supply questions matter.

It exists so later agents do not have to rediscover the same supply-side
boundary:

- AAC/H.264 parity is not a Browser feature-flag problem.
- The remaining work is producing a compatible CEF build and feeding it through
  GhoDex's managed runtime + acceptance flow.

## Official Inputs

Use the official CEF build/tooling path:

- CEF `automate-git.py` for source checkout, build, and distribution packaging
- the matching CEF release branch for the app's Chromium line
- `GN_DEFINES` that explicitly enable the Chrome FFmpeg lane:
  `is_official_build=true proprietary_codecs=true ffmpeg_branding=Chrome`

Relevant upstream references:

- Chromium media docs say AAC and H.264 are proprietary codecs limited to the
  Google Chrome lane and describe `ffmpeg_branding` plus
  `proprietary_codecs`.
- CEF's official build docs describe `automate-git.py`, `--branch`,
  `--arm64-build`, and binary distribution packaging through `make_distrib.py`.

## Repo Workflow

1. Build a codec-enabled arm64 CEF distribution:

```bash
scripts/build_codec_enabled_cef_runtime.sh \
  --work-root /path/with-150gb-free \
  --branch 7632 \
  --managed-descriptor "$HOME/Library/Application Support/GhoDex/CEF/managed-runtime.json"
```

2. The build script drives the official CEF tooling, produces a distribution
   archive, and then calls `scripts/install_cef_runtime.sh` with:
   - `ffmpegBranding=Chrome`
   - `proprietaryCodecs=true`
   - `mediaCapabilities.h264=true`
   - `mediaCapabilities.aac=true`

3. `scripts/install_cef_runtime.sh` installs the runtime under the target CEF
   root, refreshes `current`, writes `manifest.json`, and optionally writes
   `managed-runtime.json`.

4. Validate the runtime through the actual managed-runtime lane instead of only
   forcing `GHODEX_CEF_ROOT`:

```bash
python3 scripts/browser_media_debug_acceptance.py \
  --app /path/to/GhoDex.app \
  --managed-runtime-root "$HOME/Library/Application Support/GhoDex/CEF/current" \
  --managed-runtime-descriptor "$HOME/Library/Application Support/GhoDex/CEF/managed-runtime.json" \
  --output /tmp/ghx-browser-media-debug-codec.json
```

## Why This Exists

- The Browser app can already consume descriptor/manifest metadata.
- What was missing was a durable production path from upstream CEF source to a
  locally installed managed runtime with metadata that GhoDex understands.
- This playbook keeps the final blocker operational instead of speculative.

## Current Constraint

As of March 26, 2026, the remaining uncertainty is no longer app code. It is
whether a host with sufficient build prerequisites and disk budget actually runs
the official CEF build and then passes the media acceptance probe with the
resulting artifact.
