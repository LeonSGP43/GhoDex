#!/usr/bin/env nu

# Build the macOS GhoDex app using xcodebuild with a clean environment
# to avoid Nix shell interference (NIX_LDFLAGS, NIX_CFLAGS_COMPILE, etc.).

def clean-env [] {
    {
        HOME: $env.HOME,
        PATH: "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    }
}

def expected-xcframework-mode [configuration: string] {
    if $configuration == "Debug" {
        "Debug"
    } else {
        "ReleaseFast"
    }
}

def xcframework-build-args [configuration: string] {
    if $configuration == "Debug" {
        []
    } else {
        ["--release=fast"]
    }
}

def trim-output [value: string] {
    $value | str trim
}

def git-output [repo_root: string, ...args: string] {
    let result = (^git -C $repo_root ...$args | complete)
    if $result.exit_code != 0 {
        error make {
            msg: $"git command failed: git -C ($repo_root) ($args | str join ' ')"
        }
    }

    trim-output $result.stdout
}

def git-has-dirty-tracked-state [repo_root: string] {
    let unstaged = (^git -C $repo_root diff --quiet --ignore-submodules --exit-code | complete)
    let staged = (^git -C $repo_root diff --cached --quiet --ignore-submodules --exit-code | complete)
    ($unstaged.exit_code != 0) or ($staged.exit_code != 0)
}

def build-metadata [repo_root: string, version: string, configuration: string] {
    let commit = (git-output $repo_root rev-parse HEAD)
    let branch = ((git-output $repo_root rev-parse '--abbrev-ref' HEAD) | str replace -a "/" "-")
    let dirty = (git-has-dirty-tracked-state $repo_root)
    let workspace_state = if $dirty { "dirty" } else { "clean" }
    let timestamp = (trim-output ((^date -u +"%Y-%m-%dT%H:%M:%SZ" | complete).stdout))
    let short_commit = if (($commit | str length) > 12) {
        $commit | str substring 0..12
    } else {
        $commit
    }
    let fingerprint = $"($version)+($configuration).($short_commit).($workspace_state).($timestamp)"

    {
        commit: $commit,
        branch: $branch,
        dirty: $dirty,
        workspace_state: $workspace_state,
        timestamp: $timestamp,
        configuration: $configuration,
        fingerprint: $fingerprint,
    }
}

def ensure-xcframework [macos_dir: string, configuration: string, env_map: record] {
    let xcframework = ($macos_dir | path join "GhoDexKit.xcframework")
    let mode_marker = ($xcframework | path join ".ghodex-optimize-mode")
    let expected_mode = (expected-xcframework-mode $configuration)

    if ($xcframework | path exists) and ($mode_marker | path exists) {
        let current_mode = (open $mode_marker | str trim)
        if $current_mode != $expected_mode {
            print $"Rebuilding ($xcframework) for optimize mode ($expected_mode)..."
            rm -rf $xcframework
        }
    } else {
        if ($xcframework | path exists) {
            print $"Refreshing ($xcframework) for optimize mode ($expected_mode)..."
        } else {
            print $"Missing ($xcframework), bootstrapping GhoDexKit.xcframework via Zig..."
        }
    }

    let build_args = (xcframework-build-args $configuration)

    (^env -i
        $"HOME=($env_map.HOME)"
        $"PATH=($env_map.PATH)"
        zig
        build
        ...$build_args
        -Demit-xcframework=true
        -Demit-macos-app=false
        | complete
    )

    if not (($xcframework | path exists)) {
        error make {
            msg: $"Failed to generate ($xcframework)"
        }
    }

    $expected_mode | save -f $mode_marker
}

def load-project-version [repo_root: string] {
    let version = (open ($repo_root | path join "VERSION") | str trim)
    let parsed = ($version | parse "{major}.{minor}.{patch}")
    if ($parsed | is-empty) {
        error make {
            msg: $"VERSION must use MAJOR.MINOR.PATCH, got ($version)"
        }
    }

    $version
}

def resolve-cef-mode [requested_mode: string, scheme: string] {
    let normalized = ($requested_mode | str trim | str downcase)

    if ($normalized == "" or $normalized == "auto") {
        if $scheme == "GhoDex" {
            "required"
        } else {
            "disabled"
        }
    } else if ($normalized == "required" or $normalized == "optional" or $normalized == "disabled") {
        $normalized
    } else {
        error make {
            msg: $"Unsupported --cef-mode value: ($requested_mode)"
            help: "Use one of: auto, required, optional, disabled."
        }
    }
}

def ensure-cef-gate [
    repo_root: string,
    configuration: string,
    cef_mode: string,
    cef_root: string,
    cef_framework: string,
    cef_wrapper_lib: string,
] {
    if $cef_mode != "required" {
        return
    }

    let missing_paths = (
        [
            { label: "Frameworks/Chromium Embedded Framework.framework", path: $cef_framework },
            { label: $"lib/($configuration)/libcef_dll_wrapper.a", path: $cef_wrapper_lib },
        ]
        | where { |entry| not ($entry.path | path exists) }
    )

    if ($missing_paths | is-empty) {
        return
    }

    let missing_summary = ($missing_paths | each { |entry| $"- ($entry.label): ($entry.path)" } | str join "\n")
    error make {
        msg: "CEF runtime is required for the main GhoDex app build, but the configured runtime is incomplete or missing."
        label: {
            text: $missing_summary
            span: (metadata $repo_root).span
        }
        help: ([
            $"Expected runtime root: ($cef_root)",
            "Install or point GhoDex at a compatible CEF runtime before building.",
            "The supported Browser-enabled build path now fails fast instead of silently compiling an unsupported build.",
            "If you intentionally want a no-Browser app build, rerun with `--cef-mode disabled`.",
            "See `README.md` and `browser-tab-runtime-activation.md` for the CEF activation model."
        ] | str join "\n")
    }
}

def inspect-binary-architectures [binary_path: string, label: string] {
    let result = (^lipo -archs $binary_path | complete)
    if $result.exit_code != 0 {
        let stderr = ($result.stderr | str trim)
        error make {
            msg: $"Failed to inspect architectures for ($label)."
            help: ([
                $"Path: ($binary_path)",
                (if ($stderr | is-empty) { "No lipo output was returned." } else { $stderr })
            ] | str join "\n")
        }
    }

    let arches = (
        trim-output $result.stdout
        | split row " "
        | each { |arch| $arch | str trim }
        | where { |arch| $arch != "" }
    )

    if ($arches | is-empty) {
        error make {
            msg: $"No architectures reported for ($label)."
            help: $"Path: ($binary_path)"
        }
    }

    $arches
}

def resolve-cef-arch-build-settings [
    scheme: string,
    cef_enabled: bool,
    cef_framework: string,
    cef_wrapper_lib: string,
] {
    if (not $cef_enabled) or $scheme != "GhoDex" {
        return {
            xcodebuild_args: [],
            framework_arches: [],
            wrapper_arches: [],
            common_arches: [],
        }
    }

    let framework_binary = ($cef_framework | path join "Chromium Embedded Framework")
    let framework_arches = (inspect-binary-architectures $framework_binary "CEF framework binary")
    let wrapper_arches = (inspect-binary-architectures $cef_wrapper_lib "CEF wrapper library")
    let common_arches = (
        $framework_arches
        | where { |arch| $wrapper_arches | any { |candidate| $candidate == $arch } }
    )

    if ($common_arches | is-empty) {
        error make {
            msg: "CEF runtime architecture mismatch."
            help: ([
                $"Framework arches: ($framework_arches | str join ', ')",
                $"Wrapper arches: ($wrapper_arches | str join ', ')",
                "Install a matching runtime pair or point GHODEX_CEF_ROOT at a compatible runtime."
            ] | str join "\n")
        }
    }

    if (($common_arches | length) == 1) {
        let arch = ($common_arches | get 0)
        let excluded_arch = if $arch == "arm64" {
            "x86_64"
        } else if $arch == "x86_64" {
            "arm64"
        } else {
            ""
        }
        let xcodebuild_args = if $excluded_arch == "" {
            [
                -destination $"platform=macOS,arch=($arch)"
                $"ARCHS=($arch)"
                "ONLY_ACTIVE_ARCH=YES"
            ]
        } else {
            [
                -destination $"platform=macOS,arch=($arch)"
                $"ARCHS=($arch)"
                "ONLY_ACTIVE_ARCH=YES"
                $"EXCLUDED_ARCHS=($excluded_arch)"
            ]
        }

        return {
            xcodebuild_args: $xcodebuild_args,
            framework_arches: $framework_arches,
            wrapper_arches: $wrapper_arches,
            common_arches: $common_arches,
        }
    }

    {
        xcodebuild_args: [],
        framework_arches: $framework_arches,
        wrapper_arches: $wrapper_arches,
        common_arches: $common_arches,
    }
}

def ensure-version-gate [repo_root: string, env_map: record] {
    let gate = (^env -i
        $"HOME=($env_map.HOME)"
        $"PATH=($env_map.PATH)"
        python3
        ($repo_root | path join "scripts" "version_gate.py")
        check
        --quiet
        | complete
    )

    if $gate.exit_code != 0 {
        let stderr = ($gate.stderr | str trim)
        let stdout = ($gate.stdout | str trim)
        let details = if ($stderr | is-empty) { $stdout } else { $stderr }
        error make {
            msg: "Version gate failed before macOS build."
            label: {
                text: $details
                span: (metadata $repo_root).span
            }
            help: "Run `python3 scripts/version_gate.py bump patch|minor|major` or `python3 scripts/version_gate.py sync X.Y.Z`, update CHANGELOG.md, then rebuild."
        }
    }
}

def main [
    --scheme: string = "GhoDex"        # Xcode scheme (GhoDex, GhoDex-iOS, DockTilePlugin)
    --configuration: string = "Debug"  # Build configuration (Debug, Release, ReleaseLocal)
    --action: string = "build"         # xcodebuild action (build, test, clean, etc.)
    --cef-mode: string = "auto"        # auto=require for GhoDex, disabled for non-browser targets
] {
    let macos_dir = $env.FILE_PWD
    let project = ($macos_dir | path join "GhoDex.xcodeproj")
    let build_dir = ($macos_dir | path join "build")
    let derived_data_dir = ($build_dir | path join "DerivedData")
    let repo_root = ($macos_dir | path dirname)
    let env_map = (clean-env)
    let project_version = (load-project-version $repo_root)
    let metadata = (build-metadata $repo_root $project_version $configuration)

    ensure-version-gate $repo_root $env_map

    ensure-xcframework $macos_dir $configuration $env_map

    let default_cef_root = ($env.HOME | path join "Library" "Application Support" "GhoDex" "CEF" "current")
    let cef_root = (($env.GHODEX_CEF_ROOT? | default $default_cef_root) | path expand)
    let cef_link_root = ($build_dir | path join "cef-runtime" "current")
    let wrapper_config = if $configuration == "Debug" { "Debug" } else { "Release" }
    let resolved_cef_mode = (resolve-cef-mode $cef_mode $scheme)

    mkdir ($build_dir | path join "cef-runtime")
    ^ln -sfn $cef_root $cef_link_root

    let cef_framework = ($cef_link_root | path join "Frameworks" "Chromium Embedded Framework.framework")
    let cef_wrapper_lib = ($cef_link_root | path join "lib" $wrapper_config "libcef_dll_wrapper.a")
    ensure-cef-gate $repo_root $wrapper_config $resolved_cef_mode $cef_root $cef_framework $cef_wrapper_lib

    let cef_runtime_available = (($cef_framework | path exists) and ($cef_wrapper_lib | path exists))
    let cef_enabled = if $resolved_cef_mode == "disabled" {
        false
    } else {
        $cef_runtime_available
    }
    let cef_arch_build_settings = (resolve-cef-arch-build-settings $scheme $cef_enabled $cef_framework $cef_wrapper_lib)

    let skip_testing = if $action == "test" {
        [-skip-testing GhosttyUITests]
    } else {
        []
    }

    let destination_args = if $action == "test" {
        [-destination "platform=macOS"]
    } else {
        []
    }

    let cef_build_settings = if $cef_enabled {
        [
            "GHODEX_CEF_ENABLED=1",
            $"GHODEX_CEF_ROOT=($cef_link_root)",
            'GHODEX_CEF_OTHER_LDFLAGS=-lsqlite3',
            $"GHODEX_CEF_WRAPPER_LIB=($cef_wrapper_lib)",
        ]
    } else {
        [
            "GHODEX_CEF_ENABLED=0",
            $"GHODEX_CEF_ROOT=($cef_link_root)",
            'GHODEX_CEF_OTHER_LDFLAGS=',
            "GHODEX_CEF_WRAPPER_LIB=",
        ]
    }

    (^env -i
        $"HOME=($env_map.HOME)"
        $"PATH=($env_map.PATH)"
        xcodebuild
        -project $project
        -scheme $scheme
        -configuration $configuration
        ...$destination_args
        ...$cef_arch_build_settings.xcodebuild_args
        -derivedDataPath $derived_data_dir
        $"SYMROOT=($build_dir)"
        $"MARKETING_VERSION=($project_version)"
        $"CURRENT_PROJECT_VERSION=($project_version)"
        $"GHODEX_BUILD_COMMIT=($metadata.commit)"
        $"GHODEX_BUILD_BRANCH=($metadata.branch)"
        $"GHODEX_BUILD_CONFIGURATION=($metadata.configuration)"
        $"GHODEX_BUILD_TIMESTAMP=($metadata.timestamp)"
        $"GHODEX_BUILD_WORKTREE_STATE=($metadata.workspace_state)"
        $"GHODEX_BUILD_FINGERPRINT=($metadata.fingerprint)"
        ...$skip_testing
        ...$cef_build_settings
        $action)

    if $cef_enabled and $scheme == "GhoDex" and ($action == "build" or $action == "test") {
        let app_bundle = ($build_dir | path join $configuration "GhoDex.app")
        if ($app_bundle | path exists) {
            ^bash ($repo_root | path join "scripts" "stage_cef_helper_app.sh") $app_bundle
        }
    }
}
