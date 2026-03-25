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

create_helper_bundle "$app_exec Helper" ""
create_helper_bundle "$app_exec Helper (GPU)" ".gpu"
create_helper_bundle "$app_exec Helper (Plugin)" ".plugin"
create_helper_bundle "$app_exec Helper (Renderer)" ".renderer"

/usr/bin/codesign --force --sign - --deep --timestamp=none "$helper_root/$app_exec Helper.app"
/usr/bin/codesign --force --sign - --deep --timestamp=none "$helper_root/$app_exec Helper (GPU).app"
/usr/bin/codesign --force --sign - --deep --timestamp=none "$helper_root/$app_exec Helper (Plugin).app"
/usr/bin/codesign --force --sign - --deep --timestamp=none "$helper_root/$app_exec Helper (Renderer).app"
/usr/bin/codesign --force --sign - --deep --timestamp=none "$app_bundle"
