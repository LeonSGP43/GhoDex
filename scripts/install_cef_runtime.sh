#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  install_cef_runtime.sh --source <dir-or-archive> [--destination <cef-root>]
  install_cef_runtime.sh --url <url> [--destination <cef-root>]

Installs an external CEF runtime into:
  ~/Library/Application Support/GhoDex/CEF/current

Accepted input layouts:
- Official CEF binary distribution directory containing:
    CMakeLists.txt
    cmake/
    libcef_dll/
    include/
    Release/Chromium Embedded Framework.framework
- A prepacked runtime directory containing:
    CMakeLists.txt
    cmake/
    libcef_dll/
    include/
    Frameworks/Chromium Embedded Framework.framework
  and optionally:
    lib/Debug/libcef_dll_wrapper.a
    lib/Release/libcef_dll_wrapper.a

Note:
- The CEF browser-tab integration needs libcef_dll_wrapper.
- Minimal/runtime-only packages are not sufficient on their own.
USAGE
}

source_path=""
download_url=""
destination_root="${HOME}/Library/Application Support/GhoDex/CEF"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      source_path="$2"
      shift 2
      ;;
    --url)
      download_url="$2"
      shift 2
      ;;
    --destination)
      destination_root="$2"
      shift 2
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

if [[ -z "$source_path" && -z "$download_url" ]]; then
  echo "Either --source or --url is required." >&2
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

ensure_framework_root_plist() {
  local framework_dir="$1"
  if [[ -f "$framework_dir/Resources/Info.plist" && ! -e "$framework_dir/Info.plist" ]]; then
    ln -s "Resources/Info.plist" "$framework_dir/Info.plist"
  fi
}

if [[ -n "$download_url" ]]; then
  download_name="$(basename "${download_url%%\?*}")"
  if [[ -z "$download_name" || "$download_name" == "/" ]]; then
    download_name="runtime-download.tar.bz2"
  fi

  archive_path="$workdir/$download_name"
  curl -L --fail --max-time 600 "$download_url" -o "$archive_path"
  source_path="$archive_path"
fi

resolve_root() {
  local candidate="$1"

  if [[ -f "$candidate/CMakeLists.txt" && -d "$candidate/cmake" && -d "$candidate/libcef_dll" && -d "$candidate/include" && -d "$candidate/Release/Chromium Embedded Framework.framework" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  if [[ -f "$candidate/CMakeLists.txt" && -d "$candidate/cmake" && -d "$candidate/libcef_dll" && -d "$candidate/include" && -d "$candidate/Frameworks/Chromium Embedded Framework.framework" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  local nested
  while IFS= read -r nested; do
    if [[ -f "$nested/CMakeLists.txt" && -d "$nested/cmake" && -d "$nested/libcef_dll" && -d "$nested/include" && -d "$nested/Release/Chromium Embedded Framework.framework" ]]; then
      printf '%s\n' "$nested"
      return 0
    fi
    if [[ -f "$nested/CMakeLists.txt" && -d "$nested/cmake" && -d "$nested/libcef_dll" && -d "$nested/include" && -d "$nested/Frameworks/Chromium Embedded Framework.framework" ]]; then
      printf '%s\n' "$nested"
      return 0
    fi
  done < <(find "$candidate" -mindepth 1 -maxdepth 2 -type d)

  return 1
}

materialized_source="$source_path"
if [[ -f "$source_path" ]]; then
  mkdir -p "$workdir/unpack"
  case "$source_path" in
    *.tar.bz2|*.tbz2)
      tar -xjf "$source_path" -C "$workdir/unpack"
      ;;
    *.tar.gz|*.tgz)
      tar -xzf "$source_path" -C "$workdir/unpack"
      ;;
    *.zip)
      ditto -x -k "$source_path" "$workdir/unpack"
      ;;
    *)
      echo "Unsupported archive type: $source_path" >&2
      exit 1
      ;;
  esac
  materialized_source="$workdir/unpack"
fi

runtime_root="$(resolve_root "$materialized_source" || true)"
if [[ -z "$runtime_root" ]]; then
  echo "Could not find a full CEF binary distribution under: $materialized_source" >&2
  exit 1
fi

framework_source="$runtime_root/Frameworks/Chromium Embedded Framework.framework"
if [[ ! -d "$framework_source" ]]; then
  framework_source="$runtime_root/Release/Chromium Embedded Framework.framework"
fi

if [[ ! -d "$runtime_root/include" || ! -d "$runtime_root/cmake" || ! -d "$runtime_root/libcef_dll" || ! -f "$runtime_root/CMakeLists.txt" || ! -d "$framework_source" ]]; then
  echo "Runtime is missing CMakeLists.txt, cmake/, libcef_dll/, include/, or Chromium Embedded Framework.framework" >&2
  exit 1
fi

slug="$(basename "$runtime_root")"
slug="${slug// /-}"
install_root="$destination_root/$slug"
current_root="$destination_root/current"

mkdir -p "$install_root/Frameworks"
mkdir -p "$install_root/lib"
rsync -a --delete "$runtime_root/CMakeLists.txt" "$install_root/"
rsync -a --delete "$runtime_root/cmake" "$install_root/"
rsync -a --delete "$runtime_root/libcef_dll" "$install_root/"
rsync -a --delete "$runtime_root/include" "$install_root/"
rsync -a --delete "$framework_source" "$install_root/Frameworks/"
ensure_framework_root_plist "$install_root/Frameworks/Chromium Embedded Framework.framework"

build_wrapper_config() {
  local config="$1"
  local arch="$2"
  local build_dir="$workdir/libcef_dll_wrapper-$config"

  rm -rf "$build_dir"
  cmake -S "$install_root" -B "$build_dir" -G Xcode -DPROJECT_ARCH="$arch" >/dev/null
  cmake --build "$build_dir" --config "$config" --target libcef_dll_wrapper >/dev/null

  local built_lib=""
  while IFS= read -r candidate; do
    built_lib="$candidate"
    break
  done < <(find "$build_dir" -path "*/$config/libcef_dll_wrapper.a" -o -path "*/libcef_dll_wrapper.a")

  if [[ -z "$built_lib" || ! -f "$built_lib" ]]; then
    echo "Failed to locate libcef_dll_wrapper.a for $config under $build_dir" >&2
    exit 1
  fi

  mkdir -p "$install_root/lib/$config"
  rsync -a "$built_lib" "$install_root/lib/$config/libcef_dll_wrapper.a"
}

if [[ ! -f "$install_root/lib/Debug/libcef_dll_wrapper.a" || ! -f "$install_root/lib/Release/libcef_dll_wrapper.a" ]]; then
  if ! command -v cmake >/dev/null 2>&1; then
    echo "cmake is required to build libcef_dll_wrapper" >&2
    exit 1
  fi

  arch="$(uname -m)"
  build_wrapper_config Debug "$arch"
  build_wrapper_config Release "$arch"
fi

cat > "$install_root/manifest.json" <<MANIFEST
{
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "source": "$(basename "$runtime_root")",
  "framework": "Chromium Embedded Framework.framework",
  "wrapper_debug": "lib/Debug/libcef_dll_wrapper.a",
  "wrapper_release": "lib/Release/libcef_dll_wrapper.a"
}
MANIFEST

ln -sfn "$install_root" "$current_root"

echo "Installed CEF runtime: $install_root"
echo "Updated current symlink: $current_root"
