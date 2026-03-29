#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSPACE_MAP_DIR="$ROOT_DIR/macos/Sources/Features/Workspace Map"

declare -i FAILURE_COUNT=0

fail() {
  local message="$1"
  echo "::error::${message}"
  FAILURE_COUNT+=1
}

collect_imports() {
  local file="$1"
  sed -nE 's/^[[:space:]]*import[[:space:]]+([A-Za-z0-9_]+).*/\1/p' "$file"
}

check_allowed_imports() {
  local file="$1"
  shift
  local -a allowed=("$@")

  while IFS= read -r module; do
    local matched=0
    local candidate
    for candidate in "${allowed[@]}"; do
      if [[ "$module" == "$candidate" ]]; then
        matched=1
        break
      fi
    done

    if [[ $matched -eq 0 ]]; then
      fail "${file} imports '${module}', but allowed modules are: ${allowed[*]}"
    fi
  done < <(collect_imports "$file")
}

check_forbidden_tokens() {
  local file="$1"
  shift
  local token
  for token in "$@"; do
    if grep -Fq "$token" "$file"; then
      fail "${file} contains forbidden runtime/UI token '${token}'"
    fi
  done
}

check_required_tokens() {
  local file="$1"
  shift
  local token
  for token in "$@"; do
    if ! grep -Fq "$token" "$file"; then
      fail "${file} is missing required boundary token '${token}'"
    fi
  done
}

for required_file in \
  "$WORKSPACE_MAP_DIR/WorkspaceMapContracts.swift" \
  "$WORKSPACE_MAP_DIR/WorkspaceMapProjectionService.swift" \
  "$WORKSPACE_MAP_DIR/WorkspaceMapLayoutStore.swift" \
  "$WORKSPACE_MAP_DIR/WorkspaceMapPerformance.swift" \
  "$WORKSPACE_MAP_DIR/WorkspaceMapRuntimeAdapter.swift" \
  "$WORKSPACE_MAP_DIR/WorkspaceMapCommandHandler.swift" \
  "$WORKSPACE_MAP_DIR/WorkspaceMapController.swift"; do
  if [[ ! -f "$required_file" ]]; then
    fail "Missing required Workspace Map source file: ${required_file}"
  fi
done

check_allowed_imports "$WORKSPACE_MAP_DIR/WorkspaceMapContracts.swift" Foundation
check_allowed_imports "$WORKSPACE_MAP_DIR/WorkspaceMapProjectionService.swift" Foundation
check_allowed_imports "$WORKSPACE_MAP_DIR/WorkspaceMapLayoutStore.swift" Foundation
check_allowed_imports "$WORKSPACE_MAP_DIR/WorkspaceMapPerformance.swift" Foundation
check_allowed_imports "$WORKSPACE_MAP_DIR/WorkspaceMapRuntimeAdapter.swift" Foundation
check_allowed_imports "$WORKSPACE_MAP_DIR/WorkspaceMapCommandHandler.swift" AppKit
check_allowed_imports "$WORKSPACE_MAP_DIR/WorkspaceMapController.swift" AppKit SwiftUI Combine GhoDexKit

for pure_file in \
  "$WORKSPACE_MAP_DIR/WorkspaceMapContracts.swift" \
  "$WORKSPACE_MAP_DIR/WorkspaceMapProjectionService.swift" \
  "$WORKSPACE_MAP_DIR/WorkspaceMapLayoutStore.swift" \
  "$WORKSPACE_MAP_DIR/WorkspaceMapPerformance.swift"; do
  check_forbidden_tokens \
    "$pure_file" \
    "NSView" \
    "NSWindow" \
    "NSHostingView" \
    "BrowserController" \
    "TerminalController" \
    "Ghostty.App" \
    "Ghostty.SurfaceView"
done

check_required_tokens \
  "$WORKSPACE_MAP_DIR/WorkspaceMapCommandHandler.swift" \
  "WorkspaceMapCommandPolicy.isAllowedInV1"

check_required_tokens \
  "$WORKSPACE_MAP_DIR/WorkspaceMapController.swift" \
  "WorkspaceMapCommandHandler.execute"

if [[ $FAILURE_COUNT -gt 0 ]]; then
  echo "Workspace Map boundary check failed with ${FAILURE_COUNT} violation(s)."
  exit 1
fi

echo "Workspace Map boundary check passed."
