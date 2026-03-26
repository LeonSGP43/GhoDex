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

    mkdir ($build_dir | path join "cef-runtime")
    ^ln -sfn $cef_root $cef_link_root

    let cef_framework = ($cef_link_root | path join "Frameworks" "Chromium Embedded Framework.framework")
    let cef_wrapper_lib = ($cef_link_root | path join "lib" $wrapper_config "libcef_dll_wrapper.a")
    let cef_enabled = (($cef_framework | path exists) and ($cef_wrapper_lib | path exists))

    let skip_testing = if $action == "test" {
        [-skip-testing GhosttyUITests]
    } else {
        []
    }

    let cef_build_settings = if $cef_enabled {
        [
            "GHODEX_CEF_ENABLED=1",
            $"GHODEX_CEF_ROOT=($cef_link_root)",
            'GHODEX_CEF_OTHER_LDFLAGS=',
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
