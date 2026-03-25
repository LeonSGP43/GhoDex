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

def ensure-xcframework [macos_dir: string, configuration: string, env_map: record] {
    let xcframework = ($macos_dir | path join "GhoDexKit.xcframework")
    let mode_marker = ($xcframework | path join ".ghodex-optimize-mode")
    let expected_mode = (expected-xcframework-mode $configuration)

    if ($xcframework | path exists) and ($mode_marker | path exists) {
        let current_mode = (open $mode_marker | str trim)
        if $current_mode == $expected_mode {
            return
        }
    }

    if ($xcframework | path exists) {
        print $"Rebuilding ($xcframework) for optimize mode ($expected_mode)..."
        rm -rf $xcframework
    } else {
        print $"Missing ($xcframework), bootstrapping GhoDexKit.xcframework via Zig..."
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

def main [
    --scheme: string = "GhoDex"        # Xcode scheme (GhoDex, GhoDex-iOS, DockTilePlugin)
    --configuration: string = "Debug"  # Build configuration (Debug, Release, ReleaseLocal)
    --action: string = "build"         # xcodebuild action (build, test, clean, etc.)
] {
    let macos_dir = $env.FILE_PWD
    let project = ($macos_dir | path join "GhoDex.xcodeproj")
    let build_dir = ($macos_dir | path join "build")
    let derived_data_dir = ($build_dir | path join "DerivedData")
    let env_map = (clean-env)

    ensure-xcframework $macos_dir $configuration $env_map

    # Skip UI tests for CLI-based invocations because it requires
    # special permissions.
    let skip_testing = if $action == "test" {
        [-skip-testing GhosttyUITests]
    } else {
        []
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
        ...$skip_testing
        $action)
}
