const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Action = @import("../cli.zig").ghostty.Action;
const args = @import("args.zig");

pub const Options = struct {
    _arena: ?ArenaAllocator = null,
    _arguments: std.ArrayList([:0]const u8) = .empty,

    pub fn parseManuallyHook(self: *Options, alloc: Allocator, arg: []const u8, iter: anytype) Allocator.Error!bool {
        try self._arguments.append(alloc, try alloc.dupeZ(u8, arg));
        while (iter.next()) |param| {
            try self._arguments.append(alloc, try alloc.dupeZ(u8, param));
        }
        return false;
    }

    pub fn deinit(self: *Options) void {
        if (self._arena) |arena| arena.deinit();
        self.* = undefined;
    }

    pub fn help(self: Options) !void {
        _ = self;
        return Action.help_error;
    }
};

const Request = struct {
    request_id: []const u8,
    protocol_version: ?[]const u8 = null,
    command: []const u8,
    tab_id: ?[]const u8 = null,
    parent_tab_id: ?[]const u8 = null,
    terminal_id: ?[]const u8 = null,
    scope: ?[]const u8 = null,
    text: ?[]const u8 = null,
    command_text: ?[]const u8 = null,
    working_directory: ?[]const u8 = null,
    title: ?[]const u8 = null,
    force: bool = false,
    client: []const u8 = "ghodex-cli",
    idempotency_key: ?[]const u8 = null,
    expected_generation: ?i64 = null,
    since_sequence: ?i64 = null,
    event_limit: ?u32 = null,
    mode: ?[]const u8 = null,
    since_frame_id: ?[]const u8 = null,
    max_chars: ?u32 = null,
    max_lines: ?u32 = null,
    cursor: ?[]const u8 = null,
    read_after_write_id: ?[]const u8 = null,
};

const ResponseStatus = struct {
    status: []const u8,
    error_code: ?[]const u8 = null,
    error_message: ?[]const u8 = null,
};

const ParsedCommand = struct {
    request: Request,
    socket_path: ?[]const u8 = null,
};

/// Send a command to the running GhoDex control harness and print a JSON response.
///
/// Subcommands:
///   * `handshake`
///   * `snapshot`
///   * `new-tab [--parent-tab-id=<id>] [--working-directory=<path>] [--command=<text>]`
///   * `close-tab --tab-id=<id> [--force]`
///   * `send-text --terminal-id=<id> --text=<text>`
///   * `run-command --terminal-id=<id> --command=<text>`
///   * `read-terminal --terminal-id=<id> [--scope=visible|screen] [--mode=snapshot|delta] [--since-frame-id=<id>] [--max-lines=<n>] [--max-chars=<n>] [--cursor=<cursor>] [--read-after-write-id=<id>]`
///   * `close-terminal --terminal-id=<id>`
///   * `events.subscribe [--since-sequence=<n>] [--event-limit=<n>]`
///
/// The command prints the control harness response JSON to stdout.
///
/// Available since: 1.7.0
pub fn run(alloc: Allocator) !u8 {
    var iter = try args.argsIterator(alloc);
    defer iter.deinit();

    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    const result = runArgs(alloc, &iter, stdout, stderr);
    stdout.flush() catch {};
    stderr.flush() catch {};
    return result;
}

fn runArgs(
    alloc_gpa: Allocator,
    args_iter: anytype,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    var opts: Options = .{};
    defer opts.deinit();

    args.parse(Options, alloc_gpa, &opts, args_iter) catch |err| switch (err) {
        error.ActionHelpRequested => return err,
        else => {
            try stderr.print("Error parsing args: {}\n", .{err});
            return 1;
        },
    };

    var arena = ArenaAllocator.init(alloc_gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    const parsed = parseCommand(alloc, opts._arguments.items) catch |err| switch (err) {
        error.ActionHelpRequested => return err,
        else => {
            try writeClientError(stdout, "invalid_arguments", @errorName(err));
            return 1;
        },
    };

    const request_json = try std.fmt.allocPrint(alloc, "{f}", .{std.json.fmt(parsed.request, .{})});
    const socket_path = resolveSocketPath(alloc, parsed.socket_path) catch |err| {
        const client_error = clientErrorForControlFailure(err);
        try writeClientError(stdout, client_error.code, client_error.message);
        return 1;
    };

    if (std.mem.eql(u8, parsed.request.command, "events.subscribe")) {
        const status_ok = streamSubscriptionRequest(alloc, stdout, socket_path, request_json) catch |err| {
            const client_error = clientErrorForControlFailure(err);
            try writeClientError(stdout, client_error.code, client_error.message);
            return 1;
        };
        return if (status_ok) 0 else 1;
    }

    const response = sendRequest(alloc, socket_path, request_json) catch |err| {
        const client_error = clientErrorForControlFailure(err);
        try writeClientError(stdout, client_error.code, client_error.message);
        return 1;
    };

    try stdout.writeAll(response);
    if (response.len == 0 or response[response.len - 1] != '\n') {
        try stdout.writeByte('\n');
    }

    const status_source = if (std.mem.eql(u8, parsed.request.command, "events.subscribe"))
        firstResponseLine(response)
    else
        response;

    const parsed_status = try std.json.parseFromSlice(ResponseStatus, alloc, status_source, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_status.deinit();

    if (std.mem.eql(u8, parsed_status.value.status, "ok")) return 0;
    return 1;
}

fn firstResponseLine(response: []const u8) []const u8 {
    const trimmed = std.mem.trimLeft(u8, response, "\r\n\t ");
    const end = std.mem.indexOfScalar(u8, trimmed, '\n') orelse trimmed.len;
    return trimmed[0..end];
}

fn parseCommand(alloc: Allocator, args_list: []const [:0]const u8) !ParsedCommand {
    if (args_list.len == 0) return error.MissingSubcommand;

    var result: ParsedCommand = .{
        .request = .{
            .request_id = try makeRequestId(alloc),
            .command = undefined,
        },
    };

    const subcommand = args_list[0];
    if (std.mem.eql(u8, subcommand, "-h") or std.mem.eql(u8, subcommand, "--help")) {
        return error.ActionHelpRequested;
    }

    result.request.command = subcommand;

    var index: usize = 1;
    while (index < args_list.len) : (index += 1) {
        const arg = args_list[index];
        if (std.mem.eql(u8, arg, "--force")) {
            result.request.force = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return error.ActionHelpRequested;
        }

        const key, const value = try splitFlag(arg, args_list, &index);
        if (std.mem.eql(u8, key, "socket")) {
            result.socket_path = try alloc.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "protocol-version")) {
            result.request.protocol_version = try alloc.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "tab-id")) {
            result.request.tab_id = try alloc.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "parent-tab-id")) {
            result.request.parent_tab_id = try alloc.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "terminal-id")) {
            result.request.terminal_id = try alloc.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "scope")) {
            result.request.scope = try alloc.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "text")) {
            result.request.text = try alloc.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "command")) {
            result.request.command_text = try alloc.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "working-directory")) {
            result.request.working_directory = try alloc.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "title")) {
            result.request.title = try alloc.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "client")) {
            result.request.client = try alloc.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "idempotency-key")) {
            result.request.idempotency_key = try alloc.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "expected-generation")) {
            result.request.expected_generation = try parseSignedInt(value);
        } else if (std.mem.eql(u8, key, "since-sequence")) {
            result.request.since_sequence = try parseSignedInt(value);
        } else if (std.mem.eql(u8, key, "event-limit")) {
            result.request.event_limit = try parseUnsignedInt(value);
        } else if (std.mem.eql(u8, key, "mode")) {
            result.request.mode = try alloc.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "since-frame-id")) {
            result.request.since_frame_id = try alloc.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "max-chars")) {
            result.request.max_chars = try parseUnsignedInt(value);
        } else if (std.mem.eql(u8, key, "max-lines")) {
            result.request.max_lines = try parseUnsignedInt(value);
        } else if (std.mem.eql(u8, key, "cursor")) {
            result.request.cursor = try alloc.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "read-after-write-id")) {
            result.request.read_after_write_id = try alloc.dupe(u8, value);
        } else {
            return error.UnknownFlag;
        }
    }

    try validateCommand(result.request);
    return result;
}

fn splitFlag(arg: []const u8, args_list: []const [:0]const u8, index: *usize) !struct { []const u8, []const u8 } {
    if (!std.mem.startsWith(u8, arg, "--")) return error.InvalidFlag;
    const body = arg[2..];
    if (std.mem.indexOfScalar(u8, body, '=')) |eq| {
        return .{ body[0..eq], body[eq + 1 ..] };
    }
    if (index.* + 1 >= args_list.len) return error.MissingFlagValue;
    index.* += 1;
    return .{ body, args_list[index.*] };
}

fn validateCommand(request: Request) !void {
    if (std.mem.eql(u8, request.command, "handshake") or
        std.mem.eql(u8, request.command, "snapshot") or
        std.mem.eql(u8, request.command, "events.subscribe"))
    {
        return;
    }
    if (std.mem.eql(u8, request.command, "new-tab")) {
        return;
    }
    if (std.mem.eql(u8, request.command, "close-tab")) {
        if (request.tab_id == null) return error.MissingTabId;
        return;
    }
    if (std.mem.eql(u8, request.command, "send-text")) {
        if (request.terminal_id == null) return error.MissingTerminalId;
        if (request.text == null) return error.MissingText;
        return;
    }
    if (std.mem.eql(u8, request.command, "run-command")) {
        if (request.terminal_id == null) return error.MissingTerminalId;
        if (request.command_text == null) return error.MissingCommand;
        return;
    }
    if (std.mem.eql(u8, request.command, "read-terminal")) {
        if (request.terminal_id == null) return error.MissingTerminalId;
        return;
    }
    if (std.mem.eql(u8, request.command, "close-terminal")) {
        if (request.terminal_id == null) return error.MissingTerminalId;
        return;
    }
    return error.UnknownSubcommand;
}

fn parseSignedInt(value: []const u8) !i64 {
    return std.fmt.parseInt(i64, value, 10);
}

fn parseUnsignedInt(value: []const u8) !u32 {
    return std.fmt.parseInt(u32, value, 10);
}

fn resolveSocketPath(alloc: Allocator, override_path: ?[]const u8) ![]const u8 {
    if (override_path) |path| return path;
    if (std.process.getEnvVarOwned(alloc, "GHODEX_CONTROL_SOCKET")) |env_path| return env_path else |_| {}

    const home = std.process.getEnvVarOwned(alloc, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => try alloc.dupe(u8, "."),
        else => return err,
    };
    defer alloc.free(home);
    return try resolveSocketPathForHome(alloc, home);
}

fn resolveSocketPathForHome(alloc: Allocator, home: []const u8) ![]const u8 {
    const bundle_ids = [_][]const u8{
        "com.leongong.ghodex.debug",
        "com.leongong.ghodex",
    };
    var candidates = std.ArrayList([]const u8).empty;
    defer candidates.deinit(alloc);

    for (bundle_ids) |bundle_id| {
        if (try preferredReachableSocketPathForBundle(alloc, home, bundle_id)) |socket_path| {
            try candidates.append(alloc, socket_path);
        }
    }

    if (candidates.items.len == 1) {
        return candidates.items[0];
    }
    if (candidates.items.len > 1) {
        for (candidates.items) |candidate| {
            alloc.free(candidate);
        }
        return error.AmbiguousSocketPath;
    }

    return try socketPathForBundleHome(alloc, home, bundle_ids[0]);
}

fn preferredReachableSocketPathForBundle(
    alloc: Allocator,
    home: []const u8,
    bundle_id: []const u8,
) !?[]const u8 {
    const socket_path = try socketPathForBundleHome(alloc, home, bundle_id);
    errdefer alloc.free(socket_path);
    if (try isReachableSocketPath(socket_path)) {
        return socket_path;
    }
    alloc.free(socket_path);

    const legacy_socket_path = try legacySocketPathForBundleHome(alloc, home, bundle_id);
    errdefer alloc.free(legacy_socket_path);
    if (try isReachableSocketPath(legacy_socket_path)) {
        return legacy_socket_path;
    }
    alloc.free(legacy_socket_path);

    return null;
}

fn isReachableSocketPath(socket_path: []const u8) !bool {
    const parent = std.fs.path.dirname(socket_path) orelse return false;
    var dir = std.fs.openDirAbsolute(parent, .{}) catch return false;
    defer dir.close();

    const stat = dir.statFile(std.fs.path.basename(socket_path)) catch return false;
    if (stat.kind != .unix_domain_socket) {
        return false;
    }

    var stream = std.net.connectUnixSocket(socket_path) catch return false;
    stream.close();
    return true;
}

fn socketNamespace(alloc: Allocator, bundle_id: []const u8) ![]const u8 {
    return std.fmt.allocPrint(alloc, "ghdx-{x:0>16}", .{fnv1a64(bundle_id)});
}

fn socketPathForBundleHome(alloc: Allocator, home: []const u8, bundle_id: []const u8) ![]const u8 {
    const namespace = try socketNamespace(alloc, bundle_id);
    defer alloc.free(namespace);
    return try std.fs.path.join(alloc, &.{
        home,
        "Library",
        "Caches",
        namespace,
        "ControlHarness",
        "harness.sock",
    });
}

fn legacySocketPathForBundleHome(alloc: Allocator, home: []const u8, bundle_id: []const u8) ![]const u8 {
    return try std.fs.path.join(alloc, &.{
        home,
        "Library",
        "Caches",
        bundle_id,
        "ControlHarness",
        "control-harness.sock",
    });
}

fn fnv1a64(text: []const u8) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    for (text) |byte| {
        hash ^= byte;
        hash *%= 0x100000001b3;
    }
    return hash;
}

fn sendRequest(alloc: Allocator, socket_path: []const u8, request_json: []const u8) ![]u8 {
    var stream = try openRequestStream(socket_path, request_json);
    defer stream.close();
    return try readAllAlloc(alloc, stream.handle, 1024 * 1024);
}

fn streamSubscriptionRequest(
    alloc: Allocator,
    stdout: *std.Io.Writer,
    socket_path: []const u8,
    request_json: []const u8,
) !bool {
    var stream = try openRequestStream(socket_path, request_json);
    defer stream.close();
    return try streamSubscriptionResponse(alloc, stdout, stream.handle);
}

fn openRequestStream(socket_path: []const u8, request_json: []const u8) !std.net.Stream {
    var stream = try std.net.connectUnixSocket(socket_path);
    errdefer stream.close();

    try writeAll(stream.handle, request_json);
    try std.posix.shutdown(stream.handle, .send);
    return stream;
}

fn streamSubscriptionResponse(
    alloc: Allocator,
    stdout: *std.Io.Writer,
    fd: std.posix.fd_t,
) !bool {
    var first_line = std.ArrayList(u8).empty;
    defer first_line.deinit(alloc);

    var chunk: [4096]u8 = undefined;
    var saw_response = false;
    var first_line_complete = false;

    while (true) {
        const amount = try std.posix.read(fd, &chunk);
        if (amount == 0) break;
        saw_response = true;

        const bytes = chunk[0..amount];
        if (!first_line_complete) {
            if (std.mem.indexOfScalar(u8, bytes, '\n')) |newline| {
                try first_line.appendSlice(alloc, bytes[0..newline]);
                first_line_complete = true;
            } else {
                try first_line.appendSlice(alloc, bytes);
            }

            if (first_line.items.len > 64 * 1024) return error.ResponseTooLarge;
        }

        try stdout.writeAll(bytes);
        try stdout.flush();
    }

    if (!saw_response) return error.EmptyResponse;

    const parsed_status = try std.json.parseFromSlice(ResponseStatus, alloc, firstResponseLine(first_line.items), .{
        .ignore_unknown_fields = true,
    });
    defer parsed_status.deinit();

    return std.mem.eql(u8, parsed_status.value.status, "ok");
}

fn writeAll(fd: std.posix.fd_t, bytes: []const u8) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const written = try std.posix.write(fd, bytes[offset..]);
        offset += written;
    }
}

fn readAllAlloc(alloc: Allocator, fd: std.posix.fd_t, max_bytes: usize) ![]u8 {
    var buffer = std.ArrayList(u8).empty;
    errdefer buffer.deinit(alloc);

    var chunk: [4096]u8 = undefined;
    while (true) {
        const amount = try std.posix.read(fd, &chunk);
        if (amount == 0) break;
        try buffer.appendSlice(alloc, chunk[0..amount]);
        if (buffer.items.len > max_bytes) return error.ResponseTooLarge;
    }

    return try buffer.toOwnedSlice(alloc);
}

fn makeRequestId(alloc: Allocator) ![]const u8 {
    var bytes: [8]u8 = undefined;
    std.crypto.random.bytes(&bytes);
    return try std.fmt.allocPrint(alloc, "req_{s}", .{std.fmt.bytesToHex(bytes, .lower)});
}

fn clientErrorForControlFailure(err: anyerror) struct {
    code: []const u8,
    message: []const u8,
} {
    return switch (err) {
        error.FileNotFound, error.ConnectionRefused, error.SocketNotConnected => .{
            .code = "control_unavailable",
            .message = "The GhoDex control harness is unavailable. Launch the GhoDex app and try again.",
        },
        error.AmbiguousSocketPath => .{
            .code = "control_socket_ambiguous",
            .message = "Multiple reachable GhoDex control harness sockets were found. Pass --socket or GHODEX_CONTROL_SOCKET to choose one instance.",
        },
        error.EmptyResponse => .{
            .code = "control_empty_response",
            .message = "The GhoDex control harness closed the connection without returning a response.",
        },
        error.ResponseTooLarge => .{
            .code = "control_response_too_large",
            .message = "The GhoDex control harness response exceeded the CLI safety limit.",
        },
        else => .{
            .code = "control_invalid_response",
            .message = @errorName(err),
        },
    };
}

fn writeClientError(stdout: *std.Io.Writer, code: []const u8, message: []const u8) !void {
    const payload = .{
        .request_id = "client",
        .status = "error",
        .error_code = code,
        .error_message = message,
    };
    try stdout.print("{f}\n", .{std.json.fmt(payload, .{ .whitespace = .indent_2 })});
}

test "parse control handshake command" {
    const testing = std.testing;
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const argv = [_][:0]const u8{
        "handshake",
    };

    const parsed = try parseCommand(alloc, &argv);
    try testing.expectEqualStrings("handshake", parsed.request.command);
    try testing.expect(parsed.request.tab_id == null);
    try testing.expect(parsed.request.terminal_id == null);
}

test "parse control run-command arguments" {
    const testing = std.testing;
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const argv = [_][:0]const u8{
        "run-command",
        "--terminal-id=01234567-89AB-CDEF-0123-456789ABCDEF",
        "--command",
        "git status",
        "--client",
        "automation-test",
    };

    const parsed = try parseCommand(alloc, &argv);
    try testing.expectEqualStrings("run-command", parsed.request.command);
    try testing.expectEqualStrings(
        "01234567-89AB-CDEF-0123-456789ABCDEF",
        parsed.request.terminal_id.?,
    );
    try testing.expectEqualStrings("git status", parsed.request.command_text.?);
    try testing.expectEqualStrings("automation-test", parsed.request.client);
}

test "parse control read-terminal requires terminal id" {
    const testing = std.testing;
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const argv = [_][:0]const u8{
        "read-terminal",
    };

    try testing.expectError(error.MissingTerminalId, parseCommand(alloc, &argv));
}

test "parse control events subscribe arguments" {
    const testing = std.testing;
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const argv = [_][:0]const u8{
        "events.subscribe",
        "--since-sequence=41",
        "--event-limit",
        "20",
        "--protocol-version",
        "1.0",
    };

    const parsed = try parseCommand(alloc, &argv);
    try testing.expectEqualStrings("events.subscribe", parsed.request.command);
    try testing.expectEqual(@as(?i64, 41), parsed.request.since_sequence);
    try testing.expectEqual(@as(?u32, 20), parsed.request.event_limit);
    try testing.expectEqualStrings("1.0", parsed.request.protocol_version.?);
}

test "parse control read-terminal delta arguments" {
    const testing = std.testing;
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const argv = [_][:0]const u8{
        "read-terminal",
        "--terminal-id=01234567-89AB-CDEF-0123-456789ABCDEF",
        "--mode",
        "delta",
        "--since-frame-id=frm_7",
        "--max-lines=24",
        "--max-chars=4096",
        "--cursor=120",
        "--read-after-write-id=seq_42",
    };

    const parsed = try parseCommand(alloc, &argv);
    try testing.expectEqualStrings("read-terminal", parsed.request.command);
    try testing.expectEqualStrings("delta", parsed.request.mode.?);
    try testing.expectEqualStrings("frm_7", parsed.request.since_frame_id.?);
    try testing.expectEqual(@as(?u32, 24), parsed.request.max_lines);
    try testing.expectEqual(@as(?u32, 4096), parsed.request.max_chars);
    try testing.expectEqualStrings("120", parsed.request.cursor.?);
    try testing.expectEqualStrings("seq_42", parsed.request.read_after_write_id.?);
}

test "resolveSocketPath returns the single reachable bundle socket" {
    const testing = std.testing;
    const home = try makeTestHomePath(testing.allocator);
    defer testing.allocator.free(home);
    defer std.fs.deleteTreeAbsolute(home) catch {};

    const debug_socket = try socketPathForBundleHome(testing.allocator, home, "com.leongong.ghodex.debug");
    defer testing.allocator.free(debug_socket);

    var fixture = try ListeningSocketFixture.bind(debug_socket);
    defer fixture.deinit();

    const resolved = try resolveSocketPathForHome(testing.allocator, home);
    defer testing.allocator.free(resolved);
    try testing.expectEqualStrings(debug_socket, resolved);
}

test "resolveSocketPath ignores stale files when only one bundle is reachable" {
    const testing = std.testing;
    const home = try makeTestHomePath(testing.allocator);
    defer testing.allocator.free(home);
    defer std.fs.deleteTreeAbsolute(home) catch {};

    const debug_socket = try socketPathForBundleHome(testing.allocator, home, "com.leongong.ghodex.debug");
    defer testing.allocator.free(debug_socket);
    if (std.fs.path.dirname(debug_socket)) |directory| {
        try std.fs.cwd().makePath(directory);
    }
    const stale_file = try std.fs.createFileAbsolute(debug_socket, .{});
    defer stale_file.close();
    try stale_file.writeAll("stale");

    const release_socket = try socketPathForBundleHome(testing.allocator, home, "com.leongong.ghodex");
    defer testing.allocator.free(release_socket);

    var fixture = try ListeningSocketFixture.bind(release_socket);
    defer fixture.deinit();

    const resolved = try resolveSocketPathForHome(testing.allocator, home);
    defer testing.allocator.free(resolved);
    try testing.expectEqualStrings(release_socket, resolved);
}

test "resolveSocketPath rejects multiple reachable bundle sockets" {
    const testing = std.testing;
    const home = try makeTestHomePath(testing.allocator);
    defer testing.allocator.free(home);
    defer std.fs.deleteTreeAbsolute(home) catch {};

    const debug_socket = try socketPathForBundleHome(testing.allocator, home, "com.leongong.ghodex.debug");
    defer testing.allocator.free(debug_socket);
    var debug_fixture = try ListeningSocketFixture.bind(debug_socket);
    defer debug_fixture.deinit();

    const release_socket = try socketPathForBundleHome(testing.allocator, home, "com.leongong.ghodex");
    defer testing.allocator.free(release_socket);
    var release_fixture = try ListeningSocketFixture.bind(release_socket);
    defer release_fixture.deinit();

    try testing.expectError(error.AmbiguousSocketPath, resolveSocketPathForHome(testing.allocator, home));
}

const RecordingTestWriter = struct {
    writer: std.Io.Writer = .{
        .vtable = &vtable,
        .buffer = &.{},
    },
    bytes: [128 * 1024]u8 = undefined,
    len: usize = 0,
    write_count: usize = 0,
    saw_write: std.atomic.Value(bool) = .init(false),

    const vtable: std.Io.Writer.VTable = .{
        .drain = drain,
    };

    fn buffered(self: *const RecordingTestWriter) []const u8 {
        return self.bytes[0..self.len];
    }

    fn drain(
        writer: *std.Io.Writer,
        data: []const []const u8,
        splat: usize,
    ) std.Io.Writer.Error!usize {
        const self: *RecordingTestWriter = @fieldParentPtr("writer", writer);
        self.write_count += 1;
        self.saw_write.store(true, .seq_cst);

        var written: usize = 0;
        for (data, 0..) |chunk, index| {
            const repeats: usize = if (index + 1 == data.len) splat else 1;
            var repeat_index: usize = 0;
            while (repeat_index < repeats) : (repeat_index += 1) {
                if (self.len + chunk.len > self.bytes.len) return error.WriteFailed;
                @memcpy(self.bytes[self.len..][0..chunk.len], chunk);
                self.len += chunk.len;
                written += chunk.len;
            }
        }

        return written;
    }
};

const StreamingSubscriptionTestServer = struct {
    socket_path: []const u8,
    ack: []const u8,
    event: ?[]const u8 = null,
    writer_seen: ?*std.atomic.Value(bool) = null,
    writer_seen_before_event: bool = false,
    request_bytes: [512]u8 = undefined,
    request_len: usize = 0,
    failure: ?anyerror = null,

    fn run(self: *StreamingSubscriptionTestServer) void {
        self.runInner() catch |err| {
            self.failure = err;
        };
    }

    fn runInner(self: *StreamingSubscriptionTestServer) !void {
        var address = try std.net.Address.initUnix(self.socket_path);
        const listener = try std.posix.socket(
            std.posix.AF.UNIX,
            std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC,
            0,
        );
        defer std.posix.close(listener);
        defer std.fs.deleteFileAbsolute(self.socket_path) catch {};

        try std.posix.bind(listener, &address.any, address.getOsSockLen());
        try std.posix.listen(listener, 1);

        const client = try std.posix.accept(listener, null, null, std.posix.SOCK.CLOEXEC);
        defer std.posix.close(client);

        self.request_len = try readIntoFixedBuffer(client, &self.request_bytes);

        if (self.ack.len > 0) {
            try writeAll(client, self.ack);
        }

        if (self.event) |event| {
            if (self.writer_seen) |writer_seen| {
                var attempts: usize = 0;
                while (attempts < 200 and !writer_seen.load(.seq_cst)) : (attempts += 1) {
                    std.Thread.sleep(5 * std.time.ns_per_ms);
                }
                self.writer_seen_before_event = writer_seen.load(.seq_cst);
            }

            try writeAll(client, event);
        }
    }
};

const OneShotResponseTestServer = struct {
    socket_path: []const u8,
    response: []const u8,
    request_bytes: [1024]u8 = undefined,
    request_len: usize = 0,
    failure: ?anyerror = null,

    fn run(self: *OneShotResponseTestServer) void {
        self.runInner() catch |err| {
            self.failure = err;
        };
    }

    fn runInner(self: *OneShotResponseTestServer) !void {
        var address = try std.net.Address.initUnix(self.socket_path);
        const listener = try std.posix.socket(
            std.posix.AF.UNIX,
            std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC,
            0,
        );
        defer std.posix.close(listener);
        defer std.fs.deleteFileAbsolute(self.socket_path) catch {};

        try std.posix.bind(listener, &address.any, address.getOsSockLen());
        try std.posix.listen(listener, 1);

        const client = try std.posix.accept(listener, null, null, std.posix.SOCK.CLOEXEC);
        defer std.posix.close(client);

        self.request_len = try readIntoFixedBuffer(client, &self.request_bytes);
        try writeAll(client, self.response);
    }
};

fn readIntoFixedBuffer(fd: std.posix.fd_t, buffer: []u8) !usize {
    var used: usize = 0;
    while (true) {
        const amount = try std.posix.read(fd, buffer[used..]);
        if (amount == 0) break;
        used += amount;
        if (used == buffer.len) return error.NoSpaceLeft;
    }
    return used;
}

fn makeTestSocketPath(alloc: Allocator) ![]const u8 {
    var socket_suffix: [4]u8 = undefined;
    std.crypto.random.bytes(&socket_suffix);
    return std.fmt.allocPrint(
        alloc,
        "/tmp/ghdx-control-{s}.sock",
        .{std.fmt.bytesToHex(socket_suffix, .lower)},
    );
}

fn makeTestHomePath(alloc: Allocator) ![]const u8 {
    var suffix: [4]u8 = undefined;
    std.crypto.random.bytes(&suffix);
    return std.fmt.allocPrint(
        alloc,
        "/tmp/ghdx-home-{s}",
        .{std.fmt.bytesToHex(suffix, .lower)},
    );
}

const ListeningSocketFixture = struct {
    fd: std.posix.fd_t,
    socket_path: []const u8,

    fn bind(socket_path: []const u8) !ListeningSocketFixture {
        if (std.fs.path.dirname(socket_path)) |directory| {
            try std.fs.cwd().makePath(directory);
        }

        var address = try std.net.Address.initUnix(socket_path);
        const listener = try std.posix.socket(
            std.posix.AF.UNIX,
            std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC,
            0,
        );
        errdefer std.posix.close(listener);
        errdefer std.fs.deleteFileAbsolute(socket_path) catch {};

        try std.posix.bind(listener, &address.any, address.getOsSockLen());
        try std.posix.listen(listener, 1);

        return .{
            .fd = listener,
            .socket_path = socket_path,
        };
    }

    fn deinit(self: *ListeningSocketFixture) void {
        std.posix.close(self.fd);
        std.fs.deleteFileAbsolute(self.socket_path) catch {};
    }
};

fn waitForSocketReady(socket_path: []const u8) !bool {
    var attempts: usize = 0;
    while (attempts < 200) : (attempts += 1) {
        if (std.fs.accessAbsolute(socket_path, .{})) |_| {
            return true;
        } else |_| {
            std.Thread.sleep(5 * std.time.ns_per_ms);
        }
    }
    return false;
}

test "events.subscribe streams ack before live event when replay is empty" {
    const testing = std.testing;
    const socket_path = try makeTestSocketPath(testing.allocator);
    defer testing.allocator.free(socket_path);
    defer std.fs.deleteFileAbsolute(socket_path) catch {};

    var stdout = RecordingTestWriter{};
    var stderr = RecordingTestWriter{};
    var server = StreamingSubscriptionTestServer{
        .socket_path = socket_path,
        .ack = "{\"request_id\":\"req-subscribe\",\"status\":\"ok\",\"result\":{\"subscribed\":true,\"replayed_event_count\":0,\"live_stream_open\":true}}\n",
        .event = "{\"stream_kind\":\"event\",\"sequence\":43,\"event\":{\"name\":\"terminal.input.sent\"}}\n",
        .writer_seen = &stdout.saw_write,
    };

    const thread = try std.Thread.spawn(.{}, StreamingSubscriptionTestServer.run, .{&server});
    defer thread.join();

    try testing.expect(try waitForSocketReady(socket_path));

    const argv = [_][]const u8{
        "events.subscribe",
        "--socket",
        socket_path,
        "--since-sequence=42",
        "--event-limit=2",
    };
    var iter = args.sliceIterator(&argv);
    const exit_code = try runArgs(testing.allocator, &iter, &stdout.writer, &stderr.writer);

    try testing.expectEqual(@as(u8, 0), exit_code);
    try testing.expectEqual(@as(?anyerror, null), server.failure);
    try testing.expect(server.writer_seen_before_event);
    try testing.expect(server.request_len > 0);
    try testing.expect(std.mem.indexOf(u8, server.request_bytes[0..server.request_len], "\"command\":\"events.subscribe\"") != null);
    try testing.expect(std.mem.indexOf(u8, server.request_bytes[0..server.request_len], "\"since_sequence\":42") != null);
    try testing.expect(std.mem.indexOf(u8, server.request_bytes[0..server.request_len], "\"event_limit\":2") != null);
    try testing.expect(stdout.write_count >= 2);
    try testing.expectEqualStrings(
        "{\"request_id\":\"req-subscribe\",\"status\":\"ok\",\"result\":{\"subscribed\":true,\"replayed_event_count\":0,\"live_stream_open\":true}}\n{\"stream_kind\":\"event\",\"sequence\":43,\"event\":{\"name\":\"terminal.input.sent\"}}\n",
        stdout.buffered(),
    );
    try testing.expectEqualStrings("", stderr.buffered());
}

test "events.subscribe streams a live event when event_limit is one" {
    const testing = std.testing;
    const socket_path = try makeTestSocketPath(testing.allocator);
    defer testing.allocator.free(socket_path);
    defer std.fs.deleteFileAbsolute(socket_path) catch {};

    var stdout = RecordingTestWriter{};
    var stderr = RecordingTestWriter{};
    var server = StreamingSubscriptionTestServer{
        .socket_path = socket_path,
        .ack = "{\"request_id\":\"req-limit-one\",\"status\":\"ok\",\"result\":{\"subscribed\":true,\"replayed_event_count\":0,\"live_stream_open\":true,\"event_limit\":1}}\n",
        .event = "{\"stream_kind\":\"event\",\"sequence\":44,\"event\":{\"name\":\"terminal.input.sent\"}}\n",
        .writer_seen = &stdout.saw_write,
    };

    const thread = try std.Thread.spawn(.{}, StreamingSubscriptionTestServer.run, .{&server});
    defer thread.join();
    try testing.expect(try waitForSocketReady(socket_path));

    const argv = [_][]const u8{
        "events.subscribe",
        "--socket",
        socket_path,
        "--since-sequence=99",
        "--event-limit=1",
    };
    var iter = args.sliceIterator(&argv);
    const exit_code = try runArgs(testing.allocator, &iter, &stdout.writer, &stderr.writer);

    try testing.expectEqual(@as(u8, 0), exit_code);
    try testing.expectEqual(@as(?anyerror, null), server.failure);
    try testing.expect(server.writer_seen_before_event);
    try testing.expect(std.mem.indexOf(u8, stdout.buffered(), "\"event_limit\":1") != null);
    try testing.expect(std.mem.indexOf(u8, stdout.buffered(), "\"sequence\":44") != null);
    try testing.expectEqualStrings("", stderr.buffered());
}

test "events.subscribe reports an empty response as a client error" {
    const testing = std.testing;
    const socket_path = try makeTestSocketPath(testing.allocator);
    defer testing.allocator.free(socket_path);
    defer std.fs.deleteFileAbsolute(socket_path) catch {};

    var stdout = RecordingTestWriter{};
    var stderr = RecordingTestWriter{};
    var server = StreamingSubscriptionTestServer{
        .socket_path = socket_path,
        .ack = "",
    };

    const thread = try std.Thread.spawn(.{}, StreamingSubscriptionTestServer.run, .{&server});
    defer thread.join();
    try testing.expect(try waitForSocketReady(socket_path));

    const argv = [_][]const u8{
        "events.subscribe",
        "--socket",
        socket_path,
    };
    var iter = args.sliceIterator(&argv);
    const exit_code = try runArgs(testing.allocator, &iter, &stdout.writer, &stderr.writer);

    try testing.expectEqual(@as(u8, 1), exit_code);
    try testing.expectEqual(@as(?anyerror, null), server.failure);
    try testing.expect(std.mem.indexOf(u8, stdout.buffered(), "\"control_empty_response\"") != null);
    try testing.expect(std.mem.indexOf(u8, stdout.buffered(), "closed the connection without returning a response") != null);
    try testing.expectEqualStrings("", stderr.buffered());
}

test "events.subscribe reports a truncated ack as a client error" {
    const testing = std.testing;
    const socket_path = try makeTestSocketPath(testing.allocator);
    defer testing.allocator.free(socket_path);
    defer std.fs.deleteFileAbsolute(socket_path) catch {};

    var stdout = RecordingTestWriter{};
    var stderr = RecordingTestWriter{};
    var server = StreamingSubscriptionTestServer{
        .socket_path = socket_path,
        .ack = "{\"request_id\":\"req-truncated\",\"status\":\"ok\"",
    };

    const thread = try std.Thread.spawn(.{}, StreamingSubscriptionTestServer.run, .{&server});
    defer thread.join();
    try testing.expect(try waitForSocketReady(socket_path));

    const argv = [_][]const u8{
        "events.subscribe",
        "--socket",
        socket_path,
    };
    var iter = args.sliceIterator(&argv);
    const exit_code = try runArgs(testing.allocator, &iter, &stdout.writer, &stderr.writer);

    try testing.expectEqual(@as(u8, 1), exit_code);
    try testing.expectEqual(@as(?anyerror, null), server.failure);
    try testing.expect(std.mem.indexOf(u8, stdout.buffered(), "\"control_invalid_response\"") != null);
    try testing.expect(std.mem.indexOf(u8, stdout.buffered(), "req-truncated") != null);
    try testing.expectEqualStrings("", stderr.buffered());
}

test "events.subscribe reports an oversized ack line as a client error" {
    const testing = std.testing;
    const socket_path = try makeTestSocketPath(testing.allocator);
    defer testing.allocator.free(socket_path);
    defer std.fs.deleteFileAbsolute(socket_path) catch {};

    const oversized_ack = try testing.allocator.alloc(u8, 70 * 1024);
    defer testing.allocator.free(oversized_ack);
    @memset(oversized_ack, 'a');

    var stdout = RecordingTestWriter{};
    var stderr = RecordingTestWriter{};
    var server = StreamingSubscriptionTestServer{
        .socket_path = socket_path,
        .ack = oversized_ack,
    };

    const thread = try std.Thread.spawn(.{}, StreamingSubscriptionTestServer.run, .{&server});
    defer thread.join();
    try testing.expect(try waitForSocketReady(socket_path));

    const argv = [_][]const u8{
        "events.subscribe",
        "--socket",
        socket_path,
    };
    var iter = args.sliceIterator(&argv);
    const exit_code = try runArgs(testing.allocator, &iter, &stdout.writer, &stderr.writer);

    try testing.expectEqual(@as(u8, 1), exit_code);
    try testing.expectEqual(@as(?anyerror, null), server.failure);
    try testing.expect(std.mem.indexOf(u8, stdout.buffered(), "\"control_response_too_large\"") != null);
    try testing.expect(std.mem.indexOf(u8, stdout.buffered(), "exceeded the CLI safety limit") != null);
    try testing.expectEqualStrings("", stderr.buffered());
}

test "events.subscribe succeeds when the socket closes after the ack" {
    const testing = std.testing;
    const socket_path = try makeTestSocketPath(testing.allocator);
    defer testing.allocator.free(socket_path);
    defer std.fs.deleteFileAbsolute(socket_path) catch {};

    var stdout = RecordingTestWriter{};
    var stderr = RecordingTestWriter{};
    var server = StreamingSubscriptionTestServer{
        .socket_path = socket_path,
        .ack = "{\"request_id\":\"req-ack-only\",\"status\":\"ok\",\"result\":{\"subscribed\":true,\"replayed_event_count\":0,\"live_stream_open\":true}}\n",
    };

    const thread = try std.Thread.spawn(.{}, StreamingSubscriptionTestServer.run, .{&server});
    defer thread.join();
    try testing.expect(try waitForSocketReady(socket_path));

    const argv = [_][]const u8{
        "events.subscribe",
        "--socket",
        socket_path,
        "--since-sequence=7",
    };
    var iter = args.sliceIterator(&argv);
    const exit_code = try runArgs(testing.allocator, &iter, &stdout.writer, &stderr.writer);

    try testing.expectEqual(@as(u8, 0), exit_code);
    try testing.expectEqual(@as(?anyerror, null), server.failure);
    try testing.expectEqualStrings(
        "{\"request_id\":\"req-ack-only\",\"status\":\"ok\",\"result\":{\"subscribed\":true,\"replayed_event_count\":0,\"live_stream_open\":true}}\n",
        stdout.buffered(),
    );
    try testing.expectEqualStrings("", stderr.buffered());
}

test "read-terminal forwards invalid read_after_write_id server errors" {
    const testing = std.testing;
    const socket_path = try makeTestSocketPath(testing.allocator);
    defer testing.allocator.free(socket_path);
    defer std.fs.deleteFileAbsolute(socket_path) catch {};

    var stdout = RecordingTestWriter{};
    var stderr = RecordingTestWriter{};
    var server = OneShotResponseTestServer{
        .socket_path = socket_path,
        .response =
            "{\"request_id\":\"req-read-invalid-write\",\"status\":\"error\",\"error_code\":\"invalid_argument\",\"error_message\":\"Invalid read_after_write_id: bad_write\"}\n",
    };

    const thread = try std.Thread.spawn(.{}, OneShotResponseTestServer.run, .{&server});
    defer thread.join();
    try testing.expect(try waitForSocketReady(socket_path));

    const argv = [_][]const u8{
        "read-terminal",
        "--socket",
        socket_path,
        "--terminal-id=01234567-89AB-CDEF-0123-456789ABCDEF",
        "--scope=screen",
        "--mode=delta",
        "--read-after-write-id=bad_write",
    };
    var iter = args.sliceIterator(&argv);
    const exit_code = try runArgs(testing.allocator, &iter, &stdout.writer, &stderr.writer);

    try testing.expectEqual(@as(u8, 1), exit_code);
    try testing.expectEqual(@as(?anyerror, null), server.failure);
    try testing.expect(std.mem.indexOf(u8, server.request_bytes[0..server.request_len], "\"read_after_write_id\":\"bad_write\"") != null);
    try testing.expect(std.mem.indexOf(u8, stdout.buffered(), "\"invalid_argument\"") != null);
    try testing.expect(std.mem.indexOf(u8, stdout.buffered(), "Invalid read_after_write_id: bad_write") != null);
    try testing.expectEqualStrings("", stderr.buffered());
}

test "read-terminal forwards cursor and since-frame validation errors" {
    const testing = std.testing;
    const socket_path = try makeTestSocketPath(testing.allocator);
    defer testing.allocator.free(socket_path);
    defer std.fs.deleteFileAbsolute(socket_path) catch {};

    var stdout = RecordingTestWriter{};
    var stderr = RecordingTestWriter{};
    var server = OneShotResponseTestServer{
        .socket_path = socket_path,
        .response =
            "{\"request_id\":\"req-read-cursor-since\",\"status\":\"error\",\"error_code\":\"invalid_argument\",\"error_message\":\"cursor cannot be combined with since_frame_id in delta mode\"}\n",
    };

    const thread = try std.Thread.spawn(.{}, OneShotResponseTestServer.run, .{&server});
    defer thread.join();
    try testing.expect(try waitForSocketReady(socket_path));

    const argv = [_][]const u8{
        "read-terminal",
        "--socket",
        socket_path,
        "--terminal-id=01234567-89AB-CDEF-0123-456789ABCDEF",
        "--mode=delta",
        "--since-frame-id=frm_7",
        "--cursor=120",
    };
    var iter = args.sliceIterator(&argv);
    const exit_code = try runArgs(testing.allocator, &iter, &stdout.writer, &stderr.writer);

    try testing.expectEqual(@as(u8, 1), exit_code);
    try testing.expectEqual(@as(?anyerror, null), server.failure);
    try testing.expect(std.mem.indexOf(u8, server.request_bytes[0..server.request_len], "\"since_frame_id\":\"frm_7\"") != null);
    try testing.expect(std.mem.indexOf(u8, server.request_bytes[0..server.request_len], "\"cursor\":\"120\"") != null);
    try testing.expect(std.mem.indexOf(u8, stdout.buffered(), "\"invalid_argument\"") != null);
    try testing.expect(std.mem.indexOf(u8, stdout.buffered(), "cursor cannot be combined with since_frame_id in delta mode") != null);
    try testing.expectEqualStrings("", stderr.buffered());
}

test "read-terminal reports oversized delta responses with a client error code" {
    const testing = std.testing;
    const socket_path = try makeTestSocketPath(testing.allocator);
    defer testing.allocator.free(socket_path);
    defer std.fs.deleteFileAbsolute(socket_path) catch {};

    const huge_content = try testing.allocator.alloc(u8, 1024 * 1024);
    defer testing.allocator.free(huge_content);
    @memset(huge_content, 'x');

    var response_writer = std.Io.Writer.Allocating.init(testing.allocator);
    defer response_writer.deinit();
    try response_writer.writer.print(
        "{{\"request_id\":\"req-large-delta\",\"status\":\"ok\",\"result\":{{\"terminal_id\":\"01234567-89AB-CDEF-0123-456789ABCDEF\",\"scope\":\"screen\",\"mode\":\"delta\",\"frame_id\":\"frm_99\",\"content\":\"{s}\"}}}}\n",
        .{huge_content},
    );

    var stdout = RecordingTestWriter{};
    var stderr = RecordingTestWriter{};
    var server = OneShotResponseTestServer{
        .socket_path = socket_path,
        .response = response_writer.writer.buffered(),
    };

    const thread = try std.Thread.spawn(.{}, OneShotResponseTestServer.run, .{&server});
    defer thread.join();
    try testing.expect(try waitForSocketReady(socket_path));

    const argv = [_][]const u8{
        "read-terminal",
        "--socket",
        socket_path,
        "--terminal-id=01234567-89AB-CDEF-0123-456789ABCDEF",
        "--mode=delta",
        "--since-frame-id=frm_7",
    };
    var iter = args.sliceIterator(&argv);
    const exit_code = try runArgs(testing.allocator, &iter, &stdout.writer, &stderr.writer);

    try testing.expectEqual(@as(u8, 1), exit_code);
    try testing.expectEqual(@as(?anyerror, null), server.failure);
    try testing.expect(std.mem.indexOf(u8, stdout.buffered(), "\"control_response_too_large\"") != null);
    try testing.expect(std.mem.indexOf(u8, stdout.buffered(), "exceeded the CLI safety limit") != null);
    try testing.expectEqualStrings("", stderr.buffered());
}

test "run-command forwards terminal not found errors" {
    const testing = std.testing;
    const socket_path = try makeTestSocketPath(testing.allocator);
    defer testing.allocator.free(socket_path);
    defer std.fs.deleteFileAbsolute(socket_path) catch {};

    var stdout = RecordingTestWriter{};
    var stderr = RecordingTestWriter{};
    var server = OneShotResponseTestServer{
        .socket_path = socket_path,
        .response =
            "{\"request_id\":\"req-run-missing-terminal\",\"status\":\"error\",\"error_code\":\"terminal_not_found\",\"error_message\":\"No terminal exists for terminal_id=01234567-89AB-CDEF-0123-456789ABCDEF\"}\n",
    };

    const thread = try std.Thread.spawn(.{}, OneShotResponseTestServer.run, .{&server});
    defer thread.join();
    try testing.expect(try waitForSocketReady(socket_path));

    const argv = [_][]const u8{
        "run-command",
        "--socket",
        socket_path,
        "--terminal-id=01234567-89AB-CDEF-0123-456789ABCDEF",
        "--command=echo hello",
    };
    var iter = args.sliceIterator(&argv);
    const exit_code = try runArgs(testing.allocator, &iter, &stdout.writer, &stderr.writer);

    try testing.expectEqual(@as(u8, 1), exit_code);
    try testing.expectEqual(@as(?anyerror, null), server.failure);
    try testing.expect(std.mem.indexOf(u8, server.request_bytes[0..server.request_len], "\"command\":\"run-command\"") != null);
    try testing.expect(std.mem.indexOf(u8, server.request_bytes[0..server.request_len], "\"command_text\":\"echo hello\"") != null);
    try testing.expect(std.mem.indexOf(u8, stdout.buffered(), "\"terminal_not_found\"") != null);
    try testing.expect(std.mem.indexOf(u8, stdout.buffered(), "No terminal exists for terminal_id=01234567-89AB-CDEF-0123-456789ABCDEF") != null);
    try testing.expectEqualStrings("", stderr.buffered());
}
