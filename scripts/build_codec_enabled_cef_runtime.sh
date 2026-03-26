#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  build_codec_enabled_cef_runtime.sh --work-root <path> [options]

Build a macOS ARM64 codec-enabled CEF distribution from official source using
CEF's automate-git.py flow, then install it into GhoDex's managed runtime root
with Chrome-like codec metadata.

Required:
  --work-root <path>             Workspace used for depot_tools + Chromium/CEF.

Optional:
  --branch <number>              CEF release branch. Default: 7632 (CEF 145).
  --depot-tools-dir <path>       Override depot_tools checkout path.
  --download-dir <path>          Override Chromium/CEF checkout path.
  --install-destination <path>   Destination CEF root. Default:
                                 ~/Library/Application Support/GhoDex/CEF
  --managed-descriptor <path>    Where to write the managed runtime descriptor.
  --slug <name>                  Installed runtime slug/managed descriptor slug.
  --runtime-source <name>        source field for manifest/descriptor metadata.
  --extra-gn-define <expr>       Extra GN_DEFINES entries appended after the
                                 codec-enabled defaults. Repeatable.
  --skip-install                 Stop after the archive is built.
  --dry-run                      Print the commands instead of executing them.

Notes:
- This workflow follows CEF's official build/docs path:
  automate-git.py + make_distrib.py via --minimal-distrib and --arm64-build.
- Official CEF docs for branch 7632 on macOS still call for roughly 150GB free
  disk space and Xcode 26.0-class tooling.
- The default GN_DEFINES are:
    is_official_build=true proprietary_codecs=true ffmpeg_branding=Chrome
USAGE
}

run() {
  if [[ "$dry_run" -eq 1 ]]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

work_root=""
branch="7632"
depot_tools_dir=""
download_dir=""
install_destination="${HOME}/Library/Application Support/GhoDex/CEF"
managed_descriptor_path=""
runtime_slug=""
runtime_source=""
skip_install=0
dry_run=0
extra_gn_defines=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --work-root)
      work_root="$2"
      shift 2
      ;;
    --branch)
      branch="$2"
      shift 2
      ;;
    --depot-tools-dir)
      depot_tools_dir="$2"
      shift 2
      ;;
    --download-dir)
      download_dir="$2"
      shift 2
      ;;
    --install-destination)
      install_destination="$2"
      shift 2
      ;;
    --managed-descriptor)
      managed_descriptor_path="$2"
      shift 2
      ;;
    --slug)
      runtime_slug="$2"
      shift 2
      ;;
    --runtime-source)
      runtime_source="$2"
      shift 2
      ;;
    --extra-gn-define)
      extra_gn_defines+=("$2")
      shift 2
      ;;
    --skip-install)
      skip_install=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$work_root" ]]; then
  echo "--work-root is required." >&2
  usage >&2
  exit 1
fi

if [[ ! "$branch" =~ ^[0-9]+$ ]]; then
  echo "--branch must be numeric." >&2
  exit 1
fi

work_root="$(python3 - "$work_root" <<'PY'
import os
import sys

print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
)"

if [[ -z "$depot_tools_dir" ]]; then
  depot_tools_dir="$work_root/depot_tools"
fi
if [[ -z "$download_dir" ]]; then
  download_dir="$work_root/chromium_git"
fi

depot_tools_dir="$(python3 - "$depot_tools_dir" <<'PY'
import os
import sys

print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
)"
download_dir="$(python3 - "$download_dir" <<'PY'
import os
import sys

print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
)"
install_destination="$(python3 - "$install_destination" <<'PY'
import os
import sys

print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
)"

automate_dir="$work_root/automate"
automate_script="$automate_dir/automate-git.py"

run mkdir -p "$work_root"
run mkdir -p "$automate_dir"
run mkdir -p "$download_dir"

if [[ ! -d "$depot_tools_dir" ]]; then
  run git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$depot_tools_dir"
fi

if [[ ! -f "$automate_script" ]]; then
  run curl -L --fail --max-time 600 https://raw.githubusercontent.com/chromiumembedded/cef/master/tools/automate/automate-git.py -o "$automate_script"
fi

gn_defines=(
  "is_official_build=true"
  "proprietary_codecs=true"
  "ffmpeg_branding=Chrome"
)
if [[ "${#extra_gn_defines[@]}" -gt 0 ]]; then
  for define in "${extra_gn_defines[@]}"; do
    gn_defines+=("$define")
  done
fi

export PATH="$depot_tools_dir:$PATH"
export GN_DEFINES="${gn_defines[*]}"

automate_cmd=(
  python3 "$automate_script"
  "--download-dir=$download_dir"
  "--depot-tools-dir=$depot_tools_dir"
  "--branch=$branch"
  --arm64-build
  --minimal-distrib
  --no-debug-build
  --force-distrib
)
run "${automate_cmd[@]}"

installer_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install_cef_runtime.sh"
if [[ "$dry_run" -eq 1 ]]; then
  echo "GN_DEFINES=$GN_DEFINES"
  echo "Dry run stops before artifact discovery."
  echo "Installer script: $installer_script"
  exit 0
fi

binary_distrib_dir="$download_dir/chromium/src/cef/binary_distrib"
if [[ ! -d "$binary_distrib_dir" ]]; then
  echo "CEF binary distribution directory not found: $binary_distrib_dir" >&2
  exit 1
fi

archive_path="$(
  find "$binary_distrib_dir" -type f \( -name "*.tar.bz2" -o -name "*.tgz" -o -name "*.tar.gz" -o -name "*.zip" \) \
    | sort \
    | tail -n 1
)"
if [[ -z "$archive_path" ]]; then
  echo "Failed to locate a generated CEF distribution archive under $binary_distrib_dir" >&2
  exit 1
fi

echo "Built codec-enabled CEF archive: $archive_path"
echo "GN_DEFINES=$GN_DEFINES"

if [[ "$skip_install" -eq 1 ]]; then
  exit 0
fi

# Resolve the installer relative to this repository instead of the runtime work root.
install_cmd=(
  "$installer_script"
  --source "$archive_path"
  --destination "$install_destination"
  --ffmpeg-branding Chrome
  --proprietary-codecs true
  --media-h264 true
  --media-aac true
  --write-managed-descriptor
)

if [[ -n "$managed_descriptor_path" ]]; then
  install_cmd=(
    "$installer_script"
    --source "$archive_path"
    --destination "$install_destination"
    --ffmpeg-branding Chrome
    --proprietary-codecs true
    --media-h264 true
    --media-aac true
    --managed-descriptor "$managed_descriptor_path"
  )
fi

if [[ -n "$runtime_slug" ]]; then
  install_cmd+=(--slug "$runtime_slug")
fi
if [[ -n "$runtime_source" ]]; then
  install_cmd+=(--runtime-source "$runtime_source")
fi

run "${install_cmd[@]}"

descriptor_target="${managed_descriptor_path:-$install_destination/managed-runtime.json}"
echo "Managed descriptor: $descriptor_target"
echo "Suggested acceptance:"
echo "  python3 scripts/browser_media_debug_acceptance.py --app /path/to/GhoDex.app --managed-runtime-root '$install_destination/current' --managed-runtime-descriptor '$descriptor_target' --output /tmp/ghx-browser-media-debug-codec.json"
