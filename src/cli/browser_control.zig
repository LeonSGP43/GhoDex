const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const args = @import("args.zig");
const Action = @import("ghostty.zig").Action;

pub const Options = struct {
    /// JSON-encoded `browser.tab.v1` request envelope.
    request: ?[]const u8 = null,

    /// Target application name or path for AppleScript.
    application: ?[]const u8 = null,

    pub fn deinit(self: Options) void {
        _ = self;
    }

    /// Enables `-h` and `--help` to work.
    pub fn help(self: Options) !void {
        _ = self;
        return Action.help_error;
    }
};

/// The `browser-control` command sends one `browser.tab.v1` JSON request to
/// the running macOS GhoDex app through the built-in AppleScript adapter and
/// prints the versioned JSON response to stdout.
///
/// This is the first local CLI bridge for Browser tab automation. The request
/// can be passed with `--request=<json>` or piped on stdin. The default target
/// application is `GhoDex`, but `--application=<name or path>` can override it.
///
/// Available since: 1.3.0
pub fn run(gpa: Allocator) !u8 {
    if (builtin.os.tag != .macos) {
        try std.io.getStdErr().writer().print(
            "+browser-control is only supported on macOS.\n",
            .{},
        );
        return 1;
    }

    var opts: Options = .{};
    defer opts.deinit();

    {
        var iter = try args.argsIterator(gpa);
        defer iter.deinit();
        try args.parse(Options, gpa, &opts, &iter);
    }

    const request_json = try resolveRequest(gpa, opts.request);
    defer gpa.free(request_json);

    const target_application = opts.application orelse "GhoDex";

    const run_result = try std.process.Child.run(.{
        .allocator = gpa,
        .argv = &.{
            "/usr/bin/osascript",
            "-e",
            "on run argv",
            "-e",
            "set targetApp to item 1 of argv",
            "-e",
            "set requestJSON to item 2 of argv",
            "-e",
            "tell application targetApp",
            "-e",
            "return run browser command protocol requestJSON",
            "-e",
            "end tell",
            "-e",
            "end run",
            target_application,
            request_json,
        },
        .max_output_bytes = 1024 * 1024,
    });
    defer {
        gpa.free(run_result.stdout);
        gpa.free(run_result.stderr);
    }

    if (run_result.stderr.len > 0) {
        try std.io.getStdErr().writer().writeAll(run_result.stderr);
        if (run_result.stderr[run_result.stderr.len - 1] != '\n') {
            try std.io.getStdErr().writer().writeByte('\n');
        }
    }

    switch (run_result.term) {
        .Exited => |code| {
            if (code != 0) return code;
        },
        else => return 1,
    }

    try std.io.getStdOut().writer().writeAll(std.mem.trim(u8, run_result.stdout, " \n\t"));
    try std.io.getStdOut().writer().writeByte('\n');
    return 0;
}

fn resolveRequest(alloc: Allocator, request: ?[]const u8) ![]u8 {
    if (request) |value| {
        const trimmed = std.mem.trim(u8, value, " \n\t");
        if (trimmed.len == 0) return error.InvalidRequest;
        return alloc.dupe(u8, trimmed);
    }

    const stdin = std.io.getStdIn();
    const data = try stdin.readToEndAlloc(alloc, 1024 * 1024);
    errdefer alloc.free(data);

    const trimmed = std.mem.trim(u8, data, " \n\t");
    if (trimmed.len == 0) return error.InvalidRequest;
    return alloc.dupe(u8, trimmed);
}
