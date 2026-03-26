const Ghostty = @This();

const std = @import("std");
const builtin = @import("builtin");
const RunStep = std.Build.Step.Run;
const Config = @import("Config.zig");
const Docs = @import("GhosttyDocs.zig");
const I18n = @import("GhosttyI18n.zig");
const Resources = @import("GhosttyResources.zig");
const XCFramework = @import("GhosttyXCFramework.zig");
const GitVersion = @import("GitVersion.zig");

build: *std.Build.Step.Run,
open: *std.Build.Step.Run,
copy: *std.Build.Step.Run,
xctest: *std.Build.Step.Run,

pub const Deps = struct {
    xcframework: *const XCFramework,
    docs: *const Docs,
    i18n: ?*const I18n,
    resources: *const Resources,
};

pub fn init(
    b: *std.Build,
    config: *const Config,
    deps: Deps,
) !Ghostty {
    const xc_config = switch (config.optimize) {
        .Debug => "Debug",
        .ReleaseSafe,
        .ReleaseSmall,
        .ReleaseFast,
        => "ReleaseLocal",
    };

    const xc_arch: ?[]const u8 = switch (deps.xcframework.target) {
        // Universal is our default target, so we don't have to
        // add anything.
        .universal => null,

        // Native we need to override the architecture in the Xcode
        // project with the -arch flag.
        .native => switch (builtin.cpu.arch) {
            .aarch64 => "arm64",
            .x86_64 => "x86_64",
            else => @panic("unsupported macOS arch"),
        },
    };

    const env = try std.process.getEnvMap(b.allocator);
    const app_path = b.fmt("macos/build/{s}/GhoDex.app", .{xc_config});
    const xctest_derived_data = b.fmt("/tmp/ghodex-zig-xcodebuild-test-{s}", .{switch (builtin.cpu.arch) {
        .aarch64 => "arm64",
        .x86_64 => "x86_64",
        else => @panic("unsupported macOS arch"),
    }});
    const xctest_destination = b.fmt("platform=macOS,arch={s}", .{switch (builtin.cpu.arch) {
        .aarch64 => "arm64",
        .x86_64 => "x86_64",
        else => @panic("unsupported macOS arch"),
    }});
    const metadata = try BuildMetadata.detect(b, config, xc_config);

    // Our step to build the Ghostty macOS app.
    const build = build: {
        // External environment variables can mess up xcodebuild, so
        // we create a new empty environment.
        const env_map = try b.allocator.create(std.process.EnvMap);
        env_map.* = .init(b.allocator);
        if (env.get("HOME")) |v| try env_map.put("HOME", v);
        if (env.get("PATH")) |v| try env_map.put("PATH", v);

        const step = RunStep.create(b, "xcodebuild");
        step.has_side_effects = true;
        step.cwd = b.path("macos");
        step.env_map = env_map;
        step.addArgs(&.{
            "xcodebuild",
            "-project",
            "GhoDex.xcodeproj",
            "-scheme",
            "GhoDex",
            "-configuration",
            xc_config,
            b.fmt("MARKETING_VERSION={d}.{d}.{d}", .{
                config.version.major,
                config.version.minor,
                config.version.patch,
            }),
            b.fmt("CURRENT_PROJECT_VERSION={d}.{d}.{d}", .{
                config.version.major,
                config.version.minor,
                config.version.patch,
            }),
            b.fmt("GHODEX_BUILD_COMMIT={s}", .{metadata.commit}),
            b.fmt("GHODEX_BUILD_BRANCH={s}", .{metadata.branch}),
            b.fmt("GHODEX_BUILD_CONFIGURATION={s}", .{xc_config}),
            b.fmt("GHODEX_BUILD_TIMESTAMP={s}", .{metadata.timestamp}),
            b.fmt("GHODEX_BUILD_WORKTREE_STATE={s}", .{metadata.workspace_state}),
            b.fmt("GHODEX_BUILD_FINGERPRINT={s}", .{metadata.fingerprint}),
        });

        // If we have a specific architecture, we need to pass it
        // to xcodebuild.
        if (xc_arch) |arch| step.addArgs(&.{ "-arch", arch });

        // We need the xcframework
        deps.xcframework.addStepDependencies(&step.step);

        // We also need all these resources because the xcode project
        // references them via symlinks.
        deps.resources.addStepDependencies(&step.step);
        if (deps.i18n) |v| v.addStepDependencies(&step.step);
        deps.docs.installDummy(&step.step);

        // Expect success
        step.expectExitCode(0);

        break :build step;
    };

    const xctest = xctest: {
        const env_map = try b.allocator.create(std.process.EnvMap);
        env_map.* = .init(b.allocator);
        if (env.get("HOME")) |v| try env_map.put("HOME", v);
        if (env.get("PATH")) |v| try env_map.put("PATH", v);

        const step = RunStep.create(b, "xcodebuild test");
        step.has_side_effects = true;
        step.cwd = b.path("macos");
        step.env_map = env_map;
        step.addArgs(&.{
            "xcodebuild",
            "test",
            "-project",
            "GhoDex.xcodeproj",
            "-scheme",
            "GhoDex",
            "-configuration",
            xc_config,
            "-destination",
            xctest_destination,
            "-derivedDataPath",
            xctest_derived_data,
            "-skip-testing",
            "GhosttyUITests",
            b.fmt("MARKETING_VERSION={d}.{d}.{d}", .{
                config.version.major,
                config.version.minor,
                config.version.patch,
            }),
            b.fmt("CURRENT_PROJECT_VERSION={d}.{d}.{d}", .{
                config.version.major,
                config.version.minor,
                config.version.patch,
            }),
            b.fmt("GHODEX_BUILD_COMMIT={s}", .{metadata.commit}),
            b.fmt("GHODEX_BUILD_BRANCH={s}", .{metadata.branch}),
            b.fmt("GHODEX_BUILD_CONFIGURATION={s}", .{xc_config}),
            b.fmt("GHODEX_BUILD_TIMESTAMP={s}", .{metadata.timestamp}),
            b.fmt("GHODEX_BUILD_WORKTREE_STATE={s}", .{metadata.workspace_state}),
            b.fmt("GHODEX_BUILD_FINGERPRINT={s}", .{metadata.fingerprint}),
        });

        // The explicit destination already selects the host architecture.
        // Passing -arch again makes xcodebuild reject the invocation.

        // We need the xcframework
        deps.xcframework.addStepDependencies(&step.step);

        // We also need all these resources because the xcode project
        // references them via symlinks.
        deps.resources.addStepDependencies(&step.step);
        if (deps.i18n) |v| v.addStepDependencies(&step.step);
        deps.docs.installDummy(&step.step);

        // Expect success
        step.expectExitCode(0);

        break :xctest step;
    };

    // Our step to open the resulting GhoDex app.
    const open = open: {
        const disable_save_state = RunStep.create(b, "disable save state");
        disable_save_state.has_side_effects = true;
        disable_save_state.addArgs(&.{
            "/usr/libexec/PlistBuddy",
            "-c",
            // We'll have to change this to `Set` if we ever put this
            // into our Info.plist.
            "Add :NSQuitAlwaysKeepsWindows bool false",
            b.fmt("{s}/Contents/Info.plist", .{app_path}),
        });
        disable_save_state.expectExitCode(0);
        disable_save_state.step.dependOn(&build.step);

        const open = RunStep.create(b, "run GhoDex app");
        open.has_side_effects = true;
        open.cwd = b.path("");
        open.addArgs(&.{b.fmt(
            "{s}/Contents/MacOS/GhoDex",
            .{app_path},
        )});

        // Open depends on the app
        open.step.dependOn(&build.step);
        open.step.dependOn(&disable_save_state.step);

        // This overrides our default behavior and forces logs to show
        // up on stderr (in addition to the centralized macOS log).
        open.setEnvironmentVariable("GHOSTTY_LOG", "stderr,macos");

        // Configure how we're launching
        open.setEnvironmentVariable("GHOSTTY_MAC_LAUNCH_SOURCE", "zig_run");

        if (b.args) |args| {
            open.addArgs(args);
        }

        break :open open;
    };

    // Our step to copy the app bundle to the install path.
    // We have to use `cp -R` because there are symlinks in the
    // bundle.
    const copy = copy: {
        const step = RunStep.create(b, "copy app bundle");
        step.addArgs(&.{ "cp", "-R" });
        step.addFileArg(b.path(app_path));
        step.addArg(b.fmt("{s}", .{b.install_path}));
        step.step.dependOn(&build.step);
        break :copy step;
    };

    return .{
        .build = build,
        .open = open,
        .copy = copy,
        .xctest = xctest,
    };
}

const BuildMetadata = struct {
    commit: []const u8,
    branch: []const u8,
    timestamp: []const u8,
    workspace_state: []const u8,
    fingerprint: []const u8,

    fn detect(
        b: *std.Build,
        config: *const Config,
        configuration: []const u8,
    ) !BuildMetadata {
        const version = b.fmt("{d}.{d}.{d}", .{
            config.version.major,
            config.version.minor,
            config.version.patch,
        });

        const git = GitVersion.detect(b) catch |err| switch (err) {
            error.GitNotFound,
            error.GitNotRepository,
            => null,
            else => return err,
        };

        const commit = if (git) |value| value.full_hash else "unknown";
        const branch = if (git) |value| value.branch else "unknown";
        const workspace_state = if (git != null and git.?.changes) "dirty" else "clean";
        const timestamp = try detectBuildTimestamp(b);
        const short_commit = if (commit.len > 12) commit[0..12] else commit;
        const fingerprint = b.fmt(
            "{s}+{s}.{s}.{s}.{s}",
            .{ version, configuration, short_commit, workspace_state, timestamp },
        );

        return .{
            .commit = commit,
            .branch = branch,
            .timestamp = timestamp,
            .workspace_state = workspace_state,
            .fingerprint = fingerprint,
        };
    }

    fn detectBuildTimestamp(b: *std.Build) ![]const u8 {
        var code: u8 = 0;
        const output = b.runAllowFail(
            &[_][]const u8{ "date", "-u", "+%Y-%m-%dT%H:%M:%SZ" },
            &code,
            .Ignore,
        ) catch |err| switch (err) {
            error.FileNotFound => return "unknown",
            else => return err,
        };
        if (code != 0) return "unknown";
        return std.mem.trimRight(u8, output, "\r\n ");
    }
};

pub fn install(self: *const Ghostty) void {
    const b = self.copy.step.owner;
    b.getInstallStep().dependOn(&self.copy.step);
}

pub fn installXcframework(self: *const Ghostty) void {
    const b = self.build.step.owner;
    b.getInstallStep().dependOn(&self.build.step);
}

pub fn addTestStepDependencies(
    self: *const Ghostty,
    other_step: *std.Build.Step,
) void {
    other_step.dependOn(&self.xctest.step);
}
