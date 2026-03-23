#!/usr/bin/env nu

# Build the macOS GhoDex app using xcodebuild with a clean environment
# to avoid Nix shell interference (NIX_LDFLAGS, NIX_CFLAGS_COMPILE, etc.).

def clean-env [] {
    {
        HOME: $env.HOME,
        PATH: "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    }
}

def ensure-xcframework [macos_dir: string, env_map: record] {
    let xcframework = ($macos_dir | path join "GhoDexKit.xcframework")
    if ($xcframework | path exists) {
        return
    }

    print $"Missing ($xcframework), bootstrapping GhoDexKit.xcframework via Zig..."

    (^env -i
        $"HOME=($env_map.HOME)"
        $"PATH=($env_map.PATH)"
        zig
        build
        -Demit-xcframework=true
        -Demit-macos-app=false
        | complete
    )

    if not (($xcframework | path exists)) {
        error make {
            msg: $"Failed to generate ($xcframework)"
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
    let env_map = (clean-env)

    ensure-xcframework $macos_dir $env_map

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
