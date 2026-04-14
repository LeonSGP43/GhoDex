#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/GhoDex.app" >&2
  exit 1
fi

app_bundle="$1"
contents_dir="$app_bundle/Contents"
info_plist="$contents_dir/Info.plist"

if [[ ! -d "$app_bundle" || ! -f "$info_plist" ]]; then
  echo "app bundle not found: $app_bundle" >&2
  exit 1
fi

app_exec="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist")"
app_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist" 2>/dev/null || echo "1")"
app_short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist" 2>/dev/null || echo "$app_version")"

main_exec="$contents_dir/MacOS/$app_exec"
helper_root="$contents_dir/Frameworks"

detect_codesign_identity() {
  local signature_info authority

  signature_info="$(/usr/bin/codesign -dv --verbose=4 "$app_bundle" 2>&1 || true)"
  authority="$(printf '%s\n' "$signature_info" | awk -F= '/^Authority=/{print $2; exit}')"
  printf '%s' "$authority"
}

resolve_codesign_identity() {
  local requested_identity="$1"
  local sha_match

  if [[ -z "$requested_identity" || "$requested_identity" == "-" ]]; then
    printf '%s' "-"
    return 0
  fi

  if [[ "$requested_identity" =~ ^[A-F0-9]{40}$ ]]; then
    printf '%s' "$requested_identity"
    return 0
  fi

  sha_match="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | awk -v needle="$requested_identity" 'index($0, "\"" needle "\"") { print $2; exit }'
  )"

  if [[ -n "$sha_match" ]]; then
    printf '%s' "$sha_match"
    return 0
  fi

  printf '%s' "$requested_identity"
}

capture_app_entitlements() {
  local destination="$1"

  if /usr/bin/codesign -d --entitlements :- "$app_bundle" >"$destination" 2>/dev/null; then
    if [[ -s "$destination" ]]; then
      return 0
    fi
  fi

  rm -f "$destination"
  return 1
}

path_has_stable_signature() {
  local target_path="$1"
  local signature_info

  signature_info="$(/usr/bin/codesign -dv --verbose=4 "$target_path" 2>&1 || true)"
  grep -q '^Authority=' <<<"$signature_info"
}

codesign_identity="$(resolve_codesign_identity "${GHODEX_CODESIGN_IDENTITY:-$(detect_codesign_identity)}")"

app_entitlements_file=""
if [[ "$codesign_identity" != "-" ]]; then
  app_entitlements_file="$(mktemp -t ghodex-app-entitlements)"
  if ! capture_app_entitlements "$app_entitlements_file"; then
    app_entitlements_file=""
  fi
fi

cleanup_temp_files() {
  if [[ -n "$app_entitlements_file" && -f "$app_entitlements_file" ]]; then
    rm -f "$app_entitlements_file"
  fi
}

trap cleanup_temp_files EXIT

remove_signature_artifacts() {
  local target_path="$1"
  local remove_signature="${2:-1}"

  [[ -e "$target_path" ]] || return 0
  xattr -cr "$target_path" 2>/dev/null || true

  if [[ "$remove_signature" == "1" ]]; then
    /usr/bin/codesign --remove-signature "$target_path" >/dev/null 2>&1 || true
  fi
}

sign_code_path() {
  local target_path="$1"
  local sign_mode="${2:-generic}"
  local preserve_existing_signature=0
  local -a codesign_args

  if path_has_stable_signature "$target_path"; then
    preserve_existing_signature=1
  fi

  remove_signature_artifacts "$target_path" "$((1 - preserve_existing_signature))"

  codesign_args=(/usr/bin/codesign --force --sign "$codesign_identity")
  if [[ "$codesign_identity" == "-" ]]; then
    codesign_args+=(--timestamp=none)
  else
    codesign_args+=(--timestamp)
  fi

  if [[ "$preserve_existing_signature" == "1" ]]; then
    codesign_args+=(--preserve-metadata=identifier,requirements,flags,runtime,entitlements)
  fi

  if [[ "$codesign_identity" != "-" ]]; then
    case "$sign_mode" in
      helper-executable|helper-bundle|app-bundle)
        codesign_args+=(--options runtime)
        ;;
    esac
  fi

  if [[ "$sign_mode" == "app-bundle" && -n "$app_entitlements_file" ]]; then
    codesign_args+=(--entitlements "$app_entitlements_file")
  fi

  codesign_args+=("$target_path")
  "${codesign_args[@]}"
}

verify_code_path() {
  local target_path="$1"

  /usr/bin/codesign --verify --deep --strict --verbose=2 "$target_path" >/dev/null
}

sign_with_retry() {
  local target_path="$1"
  local label="$2"
  local sign_mode="${3:-generic}"
  local max_attempts=2
  local attempt=1

  while (( attempt <= max_attempts )); do
    if sign_code_path "$target_path" "$sign_mode" && verify_code_path "$target_path"; then
      return 0
    fi

    if (( attempt == max_attempts )); then
      echo "codesign failed for $label after $attempt attempt(s): $target_path" >&2
      return 1
    fi

    echo "codesign retry $attempt for $label: $target_path" >&2
    sleep 1
    ((attempt++))
  done
}

stage_rpath_dependency() {
  local dependency_path="$1"
  local framework_root framework_name framework_source dylib_name dylib_source

  case "$dependency_path" in
    @rpath/*.framework/*)
      framework_root="${dependency_path#@rpath/}"
      framework_name="${framework_root%%/*}"
      framework_source="$contents_dir/Frameworks/$framework_name"

      if [[ -d "$framework_source" && ! -e "$helper_frameworks/$framework_name" ]]; then
        cp -R "$framework_source" "$helper_frameworks/$framework_name"
      fi
      ;;
    @rpath/*.dylib)
      dylib_name="${dependency_path#@rpath/}"

      for dylib_source in \
        "$contents_dir/MacOS/$dylib_name" \
        "$contents_dir/Frameworks/$dylib_name"
      do
        if [[ -f "$dylib_source" && ! -e "$helper_frameworks/$dylib_name" ]]; then
          cp "$dylib_source" "$helper_frameworks/$dylib_name"
          chmod 644 "$helper_frameworks/$dylib_name"
          break
        fi
      done
      ;;
  esac
}

collect_rpath_dependencies() {
  local binary_path="$1"
  local dependency dependency_path

  while IFS= read -r dependency; do
    dependency="${dependency#"${dependency%%[![:space:]]*}"}"
    dependency_path="${dependency%% *}"
    stage_rpath_dependency "$dependency_path"
  done < <(otool -L "$binary_path" | tail -n +2)
}

create_helper_bundle() {
  local helper_name="$1"
  local helper_id_suffix="$2"
  local helper_bundle="$helper_root/$helper_name.app"
  local helper_contents="$helper_bundle/Contents"
  local helper_exec="$helper_contents/MacOS/$helper_name"
  local helper_info="$helper_contents/Info.plist"
  local helper_frameworks="$helper_contents/Frameworks"

  rm -rf "$helper_bundle"
  mkdir -p "$helper_contents/MacOS" "$helper_frameworks"

  cp "$main_exec" "$helper_exec"
  chmod 755 "$helper_exec"

  collect_rpath_dependencies "$main_exec"

  while IFS= read -r dependency_path; do
    [[ -f "$helper_frameworks/$dependency_path" ]] || continue
    collect_rpath_dependencies "$helper_frameworks/$dependency_path"
  done < <(find "$helper_frameworks" -maxdepth 1 -type f -name '*.dylib' -exec basename {} \;)

  cat >"$helper_info" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$helper_name</string>
  <key>CFBundleIdentifier</key>
  <string>$app_id.helper$helper_id_suffix</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$helper_name</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$app_short_version</string>
  <key>CFBundleVersion</key>
  <string>$app_version</string>
  <key>LSBackgroundOnly</key>
  <true/>
</dict>
</plist>
EOF
}

sign_helper_bundle() {
  local helper_bundle="$1"
  local helper_contents="$helper_bundle/Contents"
  local helper_exec

  helper_exec="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$helper_contents/Info.plist")"

  while IFS= read -r nested_path; do
    sign_with_retry "$nested_path" "nested helper code"
  done < <(
    find "$helper_contents" -depth \( \
      -type f -path "$helper_contents/MacOS/*" \
      -o -type f -name '*.dylib' \
      -o -type d -name '*.framework' \
      -o -type d -name '*.xpc' \
      -o -type d -name '*.app' \
    \) -print
  )

  sign_with_retry "$helper_contents/MacOS/$helper_exec" "helper executable" "helper-executable"
  sign_with_retry "$helper_bundle" "helper bundle" "helper-bundle"
}

create_helper_bundle "$app_exec Helper" ""
create_helper_bundle "$app_exec Helper (GPU)" ".gpu"
create_helper_bundle "$app_exec Helper (Plugin)" ".plugin"
create_helper_bundle "$app_exec Helper (Renderer)" ".renderer"

sign_helper_bundle "$helper_root/$app_exec Helper.app"
sign_helper_bundle "$helper_root/$app_exec Helper (GPU).app"
sign_helper_bundle "$helper_root/$app_exec Helper (Plugin).app"
sign_helper_bundle "$helper_root/$app_exec Helper (Renderer).app"
sign_with_retry "$contents_dir/PlugIns/DockTilePlugin.plugin" "dock tile plugin"
sign_with_retry "$app_bundle" "app bundle" "app-bundle"
