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
///   * `read-terminal --terminal-id=<id> [--scope=visible|screen]`
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
    const socket_path = try resolveSocketPath(alloc, parsed.socket_path);

    const response = sendRequest(alloc, socket_path, request_json) catch |err| {
        const message = switch (err) {
            error.FileNotFound, error.ConnectionRefused, error.SocketNotConnected => "The GhoDex control harness is unavailable. Launch the GhoDex app and try again.",
            else => @errorName(err),
        };
        try writeClientError(stdout, "control_unavailable", message);
        return 1;
    };

    try stdout.writeAll(response);
    if (response.len == 0 or response[response.len - 1] != '\n') {
        try stdout.writeByte('\n');
    }

    const parsed_status = try std.json.parseFromSlice(ResponseStatus, alloc, response, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_status.deinit();

    if (std.mem.eql(u8, parsed_status.value.status, "ok")) return 0;
    return 1;
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

    const home = std.process.getEnvVarOwned(alloc, "HOME") catch ".";
    const bundle_ids = [_][]const u8{
        "com.leongong.ghodex.debug",
        "com.leongong.ghodex",
    };
    for (bundle_ids) |bundle_id| {
        const socket_path = try std.fs.path.join(alloc, &.{
            home,
            "Library",
            "Caches",
            bundle_id,
            "ControlHarness",
            "control-harness.sock",
        });
        if (std.fs.accessAbsolute(socket_path, .{})) |_| {
            return socket_path;
        } else |_| {}
    }

    return try std.fs.path.join(alloc, &.{
        home,
        "Library",
        "Caches",
        bundle_ids[0],
        "ControlHarness",
        "control-harness.sock",
    });
}

fn sendRequest(alloc: Allocator, socket_path: []const u8, request_json: []const u8) ![]u8 {
    var stream = try std.net.connectUnixSocket(socket_path);
    defer stream.close();

    try writeAll(stream.handle, request_json);
    try std.posix.shutdown(stream.handle, .send);
    return try readAllAlloc(alloc, stream.handle, 1024 * 1024);
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
