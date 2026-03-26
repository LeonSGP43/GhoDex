#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
VERSION_FILE = ROOT / "VERSION"
CHANGELOG_FILE = ROOT / "CHANGELOG.md"
BUILD_ZIG_ZON_FILE = ROOT / "build.zig.zon"
PBXPROJ_FILE = ROOT / "macos" / "GhoDex.xcodeproj" / "project.pbxproj"

SEMVER_RE = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
ZON_VERSION_RE = re.compile(r'(?m)^(\s*\.version\s*=\s*")([^"]+)(",\s*)$')
MARKETING_VERSION_RE = re.compile(r"(?m)^(\s*MARKETING_VERSION\s*=\s*)([^;]+)(;)$")
CURRENT_PROJECT_VERSION_RE = re.compile(
    r"(?m)^(\s*CURRENT_PROJECT_VERSION\s*=\s*)([^;]+)(;)$"
)
RELEASE_HEADING_RE = re.compile(r"^## \[(?!Unreleased\])([^\]]+)\](?:\s+-\s+.+)?$", re.MULTILINE)
CONVENTIONAL_COMMIT_RE = re.compile(r"^(?P<type>[a-z]+)(?:\([^)]+\))?(?P<breaking>!)?:\s+.+$")
VERSION_TRACKED_PATHS = (
    "VERSION",
    "CHANGELOG.md",
    "build.zig.zon",
    "macos/GhoDex.xcodeproj/project.pbxproj",
)
PUSH_BUMP_TYPES = frozenset({"feat", "fix", "perf"})


class VersionGateError(RuntimeError):
    pass


@dataclass(frozen=True)
class VersionState:
    version: str
    changelog_has_unreleased: bool
    changelog_release_headings: tuple[str, ...]
    zig_version: str
    marketing_versions: frozenset[str]
    current_project_versions: frozenset[str]


def run_git(args: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if check and completed.returncode != 0:
        raise VersionGateError((completed.stderr or completed.stdout).strip())
    return completed


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")


def normalize_version(raw: str) -> str:
    version = raw.strip()
    if not SEMVER_RE.fullmatch(version):
        raise VersionGateError(
            f"VERSION must use SemVer MAJOR.MINOR.PATCH, got: {version!r}"
        )
    return version


def read_version() -> str:
    return normalize_version(read_text(VERSION_FILE))


def read_zig_version() -> str:
    match = ZON_VERSION_RE.search(read_text(BUILD_ZIG_ZON_FILE))
    if match is None:
        raise VersionGateError("build.zig.zon is missing the top-level .version entry")
    return match.group(2).strip()


def read_xcode_versions() -> tuple[frozenset[str], frozenset[str]]:
    text = read_text(PBXPROJ_FILE)
    marketing_versions = frozenset(
        match.group(2).strip().strip('"')
        for match in MARKETING_VERSION_RE.finditer(text)
    )
    current_project_versions = frozenset(
        match.group(2).strip().strip('"')
        for match in CURRENT_PROJECT_VERSION_RE.finditer(text)
    )
    if not marketing_versions:
        raise VersionGateError("project.pbxproj does not contain MARKETING_VERSION")
    if not current_project_versions:
        raise VersionGateError("project.pbxproj does not contain CURRENT_PROJECT_VERSION")
    return marketing_versions, current_project_versions


def load_state() -> VersionState:
    version = read_version()
    changelog = read_text(CHANGELOG_FILE)
    marketing_versions, current_project_versions = read_xcode_versions()
    return VersionState(
        version=version,
        changelog_has_unreleased="## [Unreleased]" in changelog,
        changelog_release_headings=tuple(RELEASE_HEADING_RE.findall(changelog)),
        zig_version=read_zig_version(),
        marketing_versions=marketing_versions,
        current_project_versions=current_project_versions,
    )


def validate_state(state: VersionState) -> list[str]:
    errors: list[str] = []

    if not state.changelog_has_unreleased:
        errors.append("CHANGELOG.md must contain a ## [Unreleased] section")
    if not state.changelog_release_headings:
        errors.append("CHANGELOG.md must contain at least one released version heading")
    if state.zig_version != state.version:
        errors.append(
            f"build.zig.zon version {state.zig_version} does not match VERSION {state.version}"
        )
    if state.marketing_versions != frozenset({state.version}):
        errors.append(
            "project.pbxproj MARKETING_VERSION values are not fully synced to "
            f"{state.version}: {sorted(state.marketing_versions)}"
        )
    if state.current_project_versions != frozenset({state.version}):
        errors.append(
            "project.pbxproj CURRENT_PROJECT_VERSION values are not fully synced to "
            f"{state.version}: {sorted(state.current_project_versions)}"
        )

    return errors


def validate_sync_state(state: VersionState) -> list[str]:
    errors = validate_state(state)
    return [
        error
        for error in errors
        if error != "CHANGELOG.md must contain at least one released version heading"
    ]


def resolve_push_base(explicit_base: str | None) -> str:
    if explicit_base:
        run_git(["rev-parse", "--verify", explicit_base])
        return explicit_base

    upstream = run_git(
        ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
        check=False,
    )
    if upstream.returncode == 0:
        return upstream.stdout.strip()

    origin_main = run_git(["rev-parse", "--verify", "origin/main"], check=False)
    if origin_main.returncode == 0:
        return "origin/main"

    raise VersionGateError(
        "Unable to resolve a push base. Pass --base <ref> or configure an upstream branch."
    )


def get_commit_subjects(base: str) -> list[str]:
    completed = run_git(["log", "--format=%s", f"{base}..HEAD"])
    subjects = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    return list(reversed(subjects))


def get_changed_paths(base: str) -> set[str]:
    completed = run_git(["diff", "--name-only", f"{base}..HEAD"])
    return {line.strip() for line in completed.stdout.splitlines() if line.strip()}


def version_at_ref(ref: str) -> str | None:
    completed = run_git(["show", f"{ref}:VERSION"], check=False)
    if completed.returncode != 0:
        return None
    return normalize_version(completed.stdout)


def commit_requires_bump(subject: str) -> bool:
    match = CONVENTIONAL_COMMIT_RE.match(subject)
    if match is None:
        return False

    commit_type = match.group("type")
    breaking = bool(match.group("breaking"))
    return breaking or commit_type in PUSH_BUMP_TYPES


def validate_push_gate(base: str, state: VersionState) -> list[str]:
    errors = validate_state(state)
    subjects = get_commit_subjects(base)
    if not subjects:
        return errors

    changed_paths = get_changed_paths(base)
    bump_required = any(commit_requires_bump(subject) for subject in subjects)
    version_before = version_at_ref(base)
    version_changed = version_before is None or version_before != state.version
    version_paths_changed = bool(changed_paths.intersection(VERSION_TRACKED_PATHS))
    changelog_changed = "CHANGELOG.md" in changed_paths

    if bump_required and not version_changed:
        errors.append(
            "Push gate failed: branch contains ship-worthy feat/fix/perf or breaking commits, "
            f"but VERSION did not change from {base} ({state.version})."
        )

    if bump_required and not version_paths_changed:
        errors.append(
            "Push gate failed: ship-worthy changes must update version-tracked files "
            "(VERSION/build.zig.zon/project.pbxproj/CHANGELOG.md)."
        )

    if bump_required and not changelog_changed:
        errors.append(
            "Push gate failed: ship-worthy changes must update CHANGELOG.md before push."
        )

    return errors


def replace_version_assignments(text: str, regex: re.Pattern[str], version: str) -> tuple[str, int]:
    return regex.subn(lambda match: f"{match.group(1)}{version}{match.group(3)}", text)


def sync_version(version: str) -> VersionState:
    version = normalize_version(version)

    write_text(VERSION_FILE, f"{version}\n")

    build_zig_zon = read_text(BUILD_ZIG_ZON_FILE)
    build_zig_zon, zon_updates = ZON_VERSION_RE.subn(
        lambda match: f'{match.group(1)}{version}{match.group(3)}',
        build_zig_zon,
        count=1,
    )
    if zon_updates != 1:
        raise VersionGateError("Failed to update build.zig.zon version")
    write_text(BUILD_ZIG_ZON_FILE, build_zig_zon)

    pbxproj = read_text(PBXPROJ_FILE)
    pbxproj, marketing_updates = replace_version_assignments(
        pbxproj,
        MARKETING_VERSION_RE,
        version,
    )
    pbxproj, current_updates = replace_version_assignments(
        pbxproj,
        CURRENT_PROJECT_VERSION_RE,
        version,
    )
    if marketing_updates == 0 or current_updates == 0:
        raise VersionGateError("Failed to update Xcode project version settings")
    write_text(PBXPROJ_FILE, pbxproj)

    state = load_state()
    errors = validate_state(state)
    if errors:
        raise VersionGateError("\n".join(errors))
    return state


def bump_version(version: str, part: str) -> str:
    major_s, minor_s, patch_s = normalize_version(version).split(".")
    major = int(major_s)
    minor = int(minor_s)
    patch = int(patch_s)

    if part == "major":
        return f"{major + 1}.0.0"
    if part == "minor":
        return f"{major}.{minor + 1}.0"
    if part == "patch":
        return f"{major}.{minor}.{patch + 1}"

    raise VersionGateError(f"Unsupported bump part: {part}")


def command_check(args: argparse.Namespace) -> int:
    state = load_state()
    errors = validate_sync_state(state)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    if not args.quiet:
        print(
            "version gate OK: "
            f"version={state.version} "
            f"zig={state.zig_version} "
            f"marketing={sorted(state.marketing_versions)[0]} "
            f"current={sorted(state.current_project_versions)[0]}"
        )
    return 0


def command_check_push(args: argparse.Namespace) -> int:
    base = resolve_push_base(args.base)
    state = load_state()
    errors = validate_push_gate(base, state)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    if not args.quiet:
        print(f"push gate OK: base={base} version={state.version}")
    return 0


def command_show(_args: argparse.Namespace) -> int:
    state = load_state()
    print(f"version={state.version}")
    print(f"zig_version={state.zig_version}")
    print(
        "marketing_versions="
        + ",".join(sorted(state.marketing_versions))
    )
    print(
        "current_project_versions="
        + ",".join(sorted(state.current_project_versions))
    )
    return 0


def command_sync(args: argparse.Namespace) -> int:
    state = sync_version(args.version)
    print(state.version)
    return 0


def command_bump(args: argparse.Namespace) -> int:
    state = load_state()
    next_version = bump_version(state.version, args.part)
    synced = sync_version(next_version)
    print(synced.version)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Manage and validate the single-source GhoDex project version."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    check_parser = subparsers.add_parser(
        "check",
        help="Validate local version metadata sync for normal development builds.",
    )
    check_parser.add_argument("--quiet", action="store_true", help="Suppress success output.")
    check_parser.set_defaults(func=command_check)

    push_parser = subparsers.add_parser(
        "check-push",
        help="Validate the pre-push version gate against the upstream/base branch.",
    )
    push_parser.add_argument(
        "--base",
        help="Explicit git base ref to compare against. Defaults to @{upstream} or origin/main.",
    )
    push_parser.add_argument("--quiet", action="store_true", help="Suppress success output.")
    push_parser.set_defaults(func=command_check_push)

    show_parser = subparsers.add_parser(
        "show",
        help="Print the current resolved version state.",
    )
    show_parser.set_defaults(func=command_show)

    sync_parser = subparsers.add_parser(
        "sync",
        help="Set an explicit SemVer and sync VERSION/build.zig.zon/Xcode project settings.",
    )
    sync_parser.add_argument("version", help="SemVer in MAJOR.MINOR.PATCH format.")
    sync_parser.set_defaults(func=command_sync)

    bump_parser = subparsers.add_parser(
        "bump",
        help="Increment the current version and sync all tracked version files.",
    )
    bump_parser.add_argument("part", choices=("major", "minor", "patch"))
    bump_parser.set_defaults(func=command_bump)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.func(args)
    except VersionGateError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
