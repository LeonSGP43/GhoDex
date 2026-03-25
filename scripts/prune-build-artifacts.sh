#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/prune-build-artifacts.sh [--apply] [--current-only]

Defaults:
  Dry-run only. No files are deleted unless --apply is passed.

Behavior:
  - Scans the current GhoDex repo for known build-artifact directories.
  - Also scans registered Git worktrees for the same repo.
  - Also scans sibling directories named GhoDex-wt-* so stale worktree folders
    with broken git metadata can still be cleaned safely.
  - Only removes known build outputs and caches. It never touches source files,
    tracked git files, or git metadata.
EOF
}

apply=0
current_only=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      apply=1
      ;;
    --current-only)
      current_only=1
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
  shift
done

human_kb() {
  awk -v kb="${1:-0}" '
    BEGIN {
      split("KB MB GB TB", unit, " ");
      size = kb + 0;
      idx = 1;
      while (size >= 1024 && idx < 4) {
        size /= 1024;
        idx++;
      }
      if (size >= 10 || idx == 1) {
        printf "%.0f%s", size, unit[idx];
      } else {
        printf "%.1f%s", size, unit[idx];
      }
    }
  '
}

abs_dir() {
  local path="$1"
  (
    cd "$path"
    pwd -P
  )
}

repo_root="$(git rev-parse --show-toplevel)"
repo_root="$(abs_dir "$repo_root")"
common_dir="$(git -C "$repo_root" rev-parse --path-format=absolute --git-common-dir)"
common_dir="$(abs_dir "$common_dir")"
coordination_root="$(abs_dir "$(dirname "$common_dir")")"
coordination_name="$(basename "$coordination_root")"
coordination_parent="$(dirname "$coordination_root")"

matches_repo_fingerprint() {
  local path="$1"

  [[ -e "$path/.git" ]] || return 1
  [[ -f "$path/build.zig" ]] || return 1
  [[ -f "$path/macos/build.nu" ]] || return 1
  [[ -f "$path/AGENTS.md" ]] || return 1
  [[ -f "$path/VERSION" ]] || return 1
  grep -q "Agent Development Guide" "$path/AGENTS.md" || return 1
}

declare -a candidate_roots=()
declare -a candidate_reasons=()
declare -a delete_paths=()

add_candidate() {
  local path="$1"
  local reason="$2"
  local resolved
  local existing

  [[ -d "$path" ]] || return 0
  resolved="$(abs_dir "$path")"

  if [[ "${#candidate_roots[@]}" -gt 0 ]]; then
    for existing in "${candidate_roots[@]}"; do
      [[ "$existing" == "$resolved" ]] && return 0
    done
  fi

  candidate_roots+=("$resolved")
  candidate_reasons+=("$reason")
}

add_candidate "$repo_root" "current repo"

if [[ "$current_only" -eq 0 ]]; then
  while IFS= read -r line; do
    case "$line" in
      worktree\ *)
        add_candidate "${line#worktree }" "registered worktree"
        ;;
    esac
  done < <(git -C "$coordination_root" worktree list --porcelain)

  shopt -s nullglob
  for sibling in "$coordination_parent"/"$coordination_name"-wt-*; do
    reason=""
    if git -C "$sibling" rev-parse --show-toplevel >/dev/null 2>&1; then
      sibling_common_dir="$(git -C "$sibling" rev-parse --path-format=absolute --git-common-dir)"
      sibling_common_dir="$(abs_dir "$sibling_common_dir")"
      if [[ "$sibling_common_dir" == "$common_dir" ]]; then
        reason="same-repo sibling"
      fi
    fi
    if [[ -z "$reason" ]] && matches_repo_fingerprint "$sibling"; then
      reason="fingerprint-matched sibling"
    fi
    [[ -n "$reason" ]] || continue
    add_candidate "$sibling" "$reason"
  done
  shopt -u nullglob
fi

declare -a target_relpaths=(
  ".zig-cache"
  "zig-out"
  "build"
  "macos/.zig-cache"
  "macos/build"
  "macos/macos/build"
  "macos/GhoDexKit.xcframework"
  "macos/GhosttyKit.xcframework"
)

found_any=0
total_kb=0

for i in "${!candidate_roots[@]}"; do
  root="${candidate_roots[$i]}"
  reason="${candidate_reasons[$i]}"
  root_kb=0
  printed_header=0

  for rel in "${target_relpaths[@]}"; do
    path="$root/$rel"
    [[ -e "$path" ]] || continue

    kb="$(du -sk "$path" 2>/dev/null | awk 'NR == 1 { print $1 }')"
    kb="${kb:-0}"

    if [[ "$printed_header" -eq 0 ]]; then
      printf '%s [%s]\n' "$root" "$reason"
      printed_header=1
    fi

    printf '  %8s  %s\n' "$(human_kb "$kb")" "$rel"
    root_kb=$((root_kb + kb))
    total_kb=$((total_kb + kb))
    found_any=1
    delete_paths+=("$path")
  done

  if [[ "$printed_header" -eq 1 ]]; then
    printf '  %8s  total\n\n' "$(human_kb "$root_kb")"
  fi
done

if [[ "$found_any" -eq 0 ]]; then
  echo "No known build artifacts found."
  exit 0
fi

printf 'Total reclaimable: %s\n' "$(human_kb "$total_kb")"

if [[ "$apply" -eq 0 ]]; then
  echo "Dry run only. Re-run with --apply to delete the paths above."
  exit 0
fi

for path in "${delete_paths[@]}"; do
  rm -rf -- "$path"
done

printf 'Removed %d paths and reclaimed up to %s.\n' "${#delete_paths[@]}" "$(human_kb "$total_kb")"
