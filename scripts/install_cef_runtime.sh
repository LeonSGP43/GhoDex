#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  install_cef_runtime.sh --source <dir-or-archive> [options]
  install_cef_runtime.sh --url <url> [options]

Installs a CEF runtime into:
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

Options:
  --destination <path>           Install root. Default:
                                 ~/Library/Application Support/GhoDex/CEF
  --slug <name>                  Override the installed runtime directory name.
  --runtime-source <name>        Metadata source name written to manifest/descriptor.
  --ffmpeg-branding <value>      Manifest/descriptor ffmpegBranding value.
  --proprietary-codecs <bool>    Manifest/descriptor proprietaryCodecs value.
  --media-h264 <bool>            Manifest/descriptor mediaCapabilities.h264 value.
  --media-aac <bool>             Manifest/descriptor mediaCapabilities.aac value.
  --descriptor-url <url>         downloadURL written to the managed descriptor.
  --descriptor-sha256 <sha256>   archiveSHA256 written to the managed descriptor.
  --write-managed-descriptor     Write managed-runtime.json under <destination>.
  --managed-descriptor <path>    Write the managed descriptor to a custom path.

Notes:
- The browser-tab integration needs libcef_dll_wrapper.
- If wrapper libraries are missing they will be built locally with CMake.
- When writing a managed descriptor, this script prefers the original archive URL
  and SHA-256. For a local archive source it will derive a file:// URL and hash
  automatically. For a source directory you must pass --descriptor-url and
  --descriptor-sha256 explicitly.
USAGE
}

source_path=""
source_download_url=""
destination_root="${HOME}/Library/Application Support/GhoDex/CEF"
slug_override=""
runtime_source_override=""
ffmpeg_branding=""
proprietary_codecs=""
media_h264=""
media_aac=""
descriptor_download_url=""
descriptor_sha256=""
write_managed_descriptor=0
managed_descriptor_path=""

normalize_optional_bool() {
  local raw="$1"
  local lower=""
  if [[ -z "$raw" ]]; then
    printf '\n'
    return 0
  fi

  lower="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"

  case "$lower" in
    true|false)
      printf '%s\n' "$lower"
      ;;
    *)
      echo "Expected true or false, got: $raw" >&2
      exit 1
      ;;
  esac
}

sha256_file() {
  local path="$1"
  shasum -a 256 "$path" | awk '{print $1}'
}

file_uri() {
  local path="$1"
  python3 - "$path" <<'PY'
import pathlib
import sys

print(pathlib.Path(sys.argv[1]).resolve().as_uri())
PY
}

json_or_null() {
  local value="$1"
  if [[ -z "$value" ]]; then
    printf 'null\n'
  else
    printf '%s\n' "$value"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      source_path="$2"
      shift 2
      ;;
    --url)
      source_download_url="$2"
      shift 2
      ;;
    --destination)
      destination_root="$2"
      shift 2
      ;;
    --slug)
      slug_override="$2"
      shift 2
      ;;
    --runtime-source)
      runtime_source_override="$2"
      shift 2
      ;;
    --ffmpeg-branding)
      ffmpeg_branding="$2"
      shift 2
      ;;
    --proprietary-codecs)
      proprietary_codecs="$2"
      shift 2
      ;;
    --media-h264)
      media_h264="$2"
      shift 2
      ;;
    --media-aac)
      media_aac="$2"
      shift 2
      ;;
    --descriptor-url)
      descriptor_download_url="$2"
      shift 2
      ;;
    --descriptor-sha256)
      descriptor_sha256="$2"
      shift 2
      ;;
    --write-managed-descriptor)
      write_managed_descriptor=1
      shift
      ;;
    --managed-descriptor)
      write_managed_descriptor=1
      managed_descriptor_path="$2"
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

if [[ -z "$source_path" && -z "$source_download_url" ]]; then
  echo "Either --source or --url is required." >&2
  exit 1
fi

proprietary_codecs="$(normalize_optional_bool "$proprietary_codecs")"
media_h264="$(normalize_optional_bool "$media_h264")"
media_aac="$(normalize_optional_bool "$media_aac")"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

ensure_framework_root_plist() {
  local framework_dir="$1"
  if [[ -f "$framework_dir/Resources/Info.plist" && ! -e "$framework_dir/Info.plist" ]]; then
    ln -s "Resources/Info.plist" "$framework_dir/Info.plist"
  fi
}

if [[ -n "$source_download_url" ]]; then
  download_name="$(basename "${source_download_url%%\?*}")"
  if [[ -z "$download_name" || "$download_name" == "/" ]]; then
    download_name="runtime-download.tar.bz2"
  fi

  archive_path="$workdir/$download_name"
  curl -L --fail --max-time 600 "$source_download_url" -o "$archive_path"
  source_path="$archive_path"
fi

if [[ -z "$managed_descriptor_path" ]]; then
  managed_descriptor_path="$destination_root/managed-runtime.json"
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

source_path="$(python3 - "$source_path" <<'PY'
import os
import sys

print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
)"

materialized_source="$source_path"
archive_path=""
if [[ -f "$source_path" ]]; then
  archive_path="$source_path"
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

runtime_slug="${slug_override:-$(basename "$runtime_root")}"
runtime_slug="${runtime_slug// /-}"
runtime_source="${runtime_source_override:-$(basename "$runtime_root")}"
install_root="$destination_root/$runtime_slug"
current_root="$destination_root/current"

mkdir -p "$install_root/Frameworks"
mkdir -p "$install_root/lib"
rsync -a --delete "$runtime_root/CMakeLists.txt" "$install_root/"
rsync -a --delete "$runtime_root/cmake" "$install_root/"
rsync -a --delete "$runtime_root/libcef_dll" "$install_root/"
rsync -a --delete "$runtime_root/include" "$install_root/"
rsync -a --delete "$framework_source" "$install_root/Frameworks/"
if [[ -d "$runtime_root/lib" ]]; then
  rsync -a --delete "$runtime_root/lib/" "$install_root/lib/"
fi
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

if [[ -z "$descriptor_download_url" ]]; then
  if [[ -n "$source_download_url" ]]; then
    descriptor_download_url="$source_download_url"
  elif [[ -n "$archive_path" ]]; then
    descriptor_download_url="$(file_uri "$archive_path")"
  fi
fi

if [[ -z "$descriptor_sha256" && -n "$archive_path" ]]; then
  descriptor_sha256="$(sha256_file "$archive_path")"
fi

manifest_download_url="$descriptor_download_url"
manifest_archive_sha256="$descriptor_sha256"

export INSTALL_ROOT="$install_root"
export RUNTIME_SOURCE="$runtime_source"
export MANIFEST_DOWNLOAD_URL="$(json_or_null "$manifest_download_url")"
export MANIFEST_ARCHIVE_SHA256="$(json_or_null "$manifest_archive_sha256")"
export FFMPEG_BRANDING="$(json_or_null "$ffmpeg_branding")"
export PROPRIETARY_CODECS="$(json_or_null "$proprietary_codecs")"
export MEDIA_H264="$(json_or_null "$media_h264")"
export MEDIA_AAC="$(json_or_null "$media_aac")"

python3 - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path


def parse_optional(raw: str):
    if raw == "null":
        return None
    if raw == "true":
        return True
    if raw == "false":
        return False
    return raw


manifest = {
    "installedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "source": os.environ["RUNTIME_SOURCE"],
    "downloadURL": parse_optional(os.environ["MANIFEST_DOWNLOAD_URL"]),
    "archiveSHA256": parse_optional(os.environ["MANIFEST_ARCHIVE_SHA256"]),
    "ffmpegBranding": parse_optional(os.environ["FFMPEG_BRANDING"]),
    "proprietaryCodecs": parse_optional(os.environ["PROPRIETARY_CODECS"]),
    "mediaCapabilities": {
        "h264": parse_optional(os.environ["MEDIA_H264"]),
        "aac": parse_optional(os.environ["MEDIA_AAC"]),
    },
    "framework": "Frameworks/Chromium Embedded Framework.framework",
    "wrapperDebug": "lib/Debug/libcef_dll_wrapper.a",
    "wrapperRelease": "lib/Release/libcef_dll_wrapper.a",
}

Path(os.environ["INSTALL_ROOT"], "manifest.json").write_text(
    json.dumps(manifest, indent=2) + "\n",
    encoding="utf-8",
)
PY

mkdir -p "$destination_root"
ln -sfn "$install_root" "$current_root"

if [[ "$write_managed_descriptor" -eq 1 ]]; then
  if [[ -z "$descriptor_download_url" || -z "$descriptor_sha256" ]]; then
    echo "Writing a managed descriptor requires an archive URL and SHA-256." >&2
    echo "Pass --descriptor-url and --descriptor-sha256, or use a local/remote archive source." >&2
    exit 1
  fi

  mkdir -p "$(dirname "$managed_descriptor_path")"

  export MANAGED_DESCRIPTOR_PATH="$managed_descriptor_path"
  export MANAGED_SLUG="$runtime_slug"
  export DESCRIPTOR_DOWNLOAD_URL="$descriptor_download_url"
  export DESCRIPTOR_SHA256="$descriptor_sha256"

  python3 - <<'PY'
import json
import os
from pathlib import Path


def parse_optional(raw: str):
    if raw == "null":
        return None
    if raw == "true":
        return True
    if raw == "false":
        return False
    return raw


descriptor = {
    "slug": os.environ["MANAGED_SLUG"],
    "downloadURL": os.environ["DESCRIPTOR_DOWNLOAD_URL"],
    "archiveSHA256": os.environ["DESCRIPTOR_SHA256"],
    "source": os.environ["RUNTIME_SOURCE"],
    "ffmpegBranding": parse_optional(os.environ["FFMPEG_BRANDING"]),
    "proprietaryCodecs": parse_optional(os.environ["PROPRIETARY_CODECS"]),
    "mediaCapabilities": {
        "h264": parse_optional(os.environ["MEDIA_H264"]),
        "aac": parse_optional(os.environ["MEDIA_AAC"]),
    },
}

Path(os.environ["MANAGED_DESCRIPTOR_PATH"]).write_text(
    json.dumps(descriptor, indent=2) + "\n",
    encoding="utf-8",
)
PY
fi

echo "Installed CEF runtime: $install_root"
echo "Updated current symlink: $current_root"
if [[ "$write_managed_descriptor" -eq 1 ]]; then
  echo "Wrote managed runtime descriptor: $managed_descriptor_path"
fi
