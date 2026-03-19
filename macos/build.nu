#!/usr/bin/env nu

# Build the macOS GhoDex app using xcodebuild with a clean environment
# to avoid Nix shell interference (NIX_LDFLAGS, NIX_CFLAGS_COMPILE, etc.).

def main [
    --scheme: string = "GhoDex"        # Xcode scheme (GhoDex, Ghostty-iOS, DockTilePlugin)
    --configuration: string = "Debug"  # Build configuration (Debug, Release, ReleaseLocal)
    --action: string = "build"         # xcodebuild action (build, test, clean, etc.)
] {
    let project = ($env.FILE_PWD | path join "GhoDex.xcodeproj")
    let build_dir = ($env.FILE_PWD | path join "build")
    let repo_root = ($env.FILE_PWD | path dirname)
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
        $"HOME=($env.HOME)"
        "PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        xcodebuild
        -project $project
        -scheme $scheme
        -configuration $configuration
        $"SYMROOT=($build_dir)"
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
