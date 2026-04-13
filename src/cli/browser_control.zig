const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const args = @import("args.zig");
const Action = @import("ghostty.zig").Action;

const browser_control_socket_name = "browser-control.sock";
const browser_app_support_root_env = "GHODEX_BROWSER_APP_SUPPORT_ROOT";

const Transport = enum {
    auto,
    ipc,
    applescript,
};

pub const Options = struct {
    /// JSON-encoded `browser.tab.v1` request envelope.
    request: ?[]const u8 = null,

    /// Target application name or path for AppleScript.
    application: ?[]const u8 = null,

    /// Preferred browser control transport.
    transport: Transport = .auto,

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
/// the running macOS GhoDex app and prints the versioned JSON response to
/// stdout.
///
/// The command prefers the local Browser IPC socket when available so callers
/// can reuse one long-lived app-side session without paying the AppleScript
/// startup cost on every request. If the IPC socket is unavailable, the
/// default `auto` transport falls back to the built-in AppleScript adapter.
///
/// The request can be passed with `--request=<json>` or piped on stdin. The
/// default AppleScript target application is `GhoDex`, but
/// `--application=<name or path>` can override it. `--transport=ipc` forces
/// the local IPC socket, while `--transport=applescript` keeps the legacy
/// one-shot AppleScript path.
///
/// Available since: 1.3.0
pub fn run(gpa: Allocator) !u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout_writer.end() catch {};

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;
    defer stderr_writer.end() catch {};

    if (builtin.os.tag != .macos) {
        try stderr.print(
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

    if (opts.transport != .applescript) {
        const socket_path = try defaultSocketPath(gpa);
        defer gpa.free(socket_path);

        const ipc_result = sendViaIpc(gpa, socket_path, request_json) catch |err| switch (opts.transport) {
            .auto => null,
            .ipc => {
                try stderr.print(
                    "Browser IPC request failed: {}\n",
                    .{err},
                );
                return 1;
            },
            .applescript => unreachable,
        };

        if (ipc_result) |response| {
            defer gpa.free(response);
            try stdout.writeAll(response);
            try stdout.writeByte('\n');
            return 0;
        }
    }

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
        try stderr.writeAll(run_result.stderr);
        if (run_result.stderr[run_result.stderr.len - 1] != '\n') {
            try stderr.writeByte('\n');
        }
    }

    switch (run_result.term) {
        .Exited => |code| {
            if (code != 0) return code;
        },
        else => return 1,
    }

    try stdout.writeAll(std.mem.trim(u8, run_result.stdout, " \n\t"));
    try stdout.writeByte('\n');
    return 0;
}

fn sendViaIpc(
    alloc: Allocator,
    socket_path: []const u8,
    request_json: []const u8,
) !?[]u8 {
    var stream = try std.net.connectUnixSocket(socket_path);
    defer stream.close();

    try stream.writeAll(request_json);
    try stream.writeAll("\n");

    var response = std.ArrayList(u8){};
    defer response.deinit(alloc);

    var read_buffer: [1024]u8 = undefined;
    while (true) {
        const read_count = try stream.read(&read_buffer);
        if (read_count == 0) break;

        if (std.mem.indexOfScalar(u8, read_buffer[0..read_count], '\n')) |newline_index| {
            try response.appendSlice(alloc, read_buffer[0..newline_index]);
            break;
        }

        try response.appendSlice(alloc, read_buffer[0..read_count]);
        if (response.items.len >= 1024 * 1024) return error.StreamTooLong;
    }

    if (response.items.len == 0) return error.Unexpected;
    return @as(?[]u8, try alloc.dupe(u8, std.mem.trim(u8, response.items, " \n\t")));
}

fn resolveRequest(alloc: Allocator, request: ?[]const u8) ![]u8 {
    if (request) |value| {
        const trimmed = std.mem.trim(u8, value, " \n\t");
        if (trimmed.len == 0) return error.InvalidRequest;
        return alloc.dupe(u8, trimmed);
    }

    const stdin = std.fs.File.stdin();
    const data = try stdin.readToEndAlloc(alloc, 1024 * 1024);
    errdefer alloc.free(data);

    const trimmed = std.mem.trim(u8, data, " \n\t");
    if (trimmed.len == 0) return error.InvalidRequest;
    return alloc.dupe(u8, trimmed);
}

fn defaultSocketPath(alloc: Allocator) ![]u8 {
    const app_support_root = try defaultAppSupportRoot(alloc);
    defer alloc.free(app_support_root);

    return std.fs.path.join(alloc, &.{
        app_support_root,
        browser_control_socket_name,
    });
}

fn defaultAppSupportRoot(alloc: Allocator) ![]u8 {
    const override_root = std.process.getEnvVarOwned(alloc, browser_app_support_root_env) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    if (override_root) |root| {
        defer alloc.free(root);
        const trimmed = std.mem.trim(u8, root, " \n\t");
        if (trimmed.len > 0) return alloc.dupe(u8, trimmed);
    }

    const home = try std.process.getEnvVarOwned(alloc, "HOME");
    defer alloc.free(home);

    return std.fs.path.join(alloc, &.{
        home,
        "Library",
        "Application Support",
        "GhoDex",
    });
}
