#!/usr/bin/env bash
set -euo pipefail

cef_root="${1:-}"
app_bundle="${2:-}"

if [[ -z "$cef_root" || -z "$app_bundle" ]]; then
  echo "usage: stage_cef_runtime.sh <cef-root> <app-bundle>" >&2
  exit 1
fi

framework_source="$cef_root/Frameworks/Chromium Embedded Framework.framework"
framework_target="$app_bundle/Contents/Frameworks/Chromium Embedded Framework.framework"

if [[ ! -d "$framework_source" ]]; then
  echo "CEF framework not found: $framework_source" >&2
  exit 1
fi

mkdir -p "$app_bundle/Contents/Frameworks"
rm -rf "$framework_target"
rsync -a "$framework_source" "$app_bundle/Contents/Frameworks/"

if [[ -f "$framework_target/Resources/Info.plist" && ! -e "$framework_target/Info.plist" ]]; then
  ln -s "Resources/Info.plist" "$framework_target/Info.plist"
fi

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$framework_target"
  codesign --force --deep --sign - "$app_bundle"
fi

echo "Staged CEF runtime into $app_bundle"
