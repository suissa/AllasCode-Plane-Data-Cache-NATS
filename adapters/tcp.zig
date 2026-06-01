const std = @import("std");
const protocol = @import("protocol.zig");

pub const max_control_line = 4096;
pub const max_payload = 1024 * 1024 * 64;

pub const FrameKind = enum {
    line,
    payload,
};

pub const ParsedControlLine = struct {
    kind: FrameKind,
    payload_len: usize = 0,
};

pub fn deliverNatsFrames(
    allocator: std.mem.Allocator,
    reader: anytype,
    ctx: *protocol.HandlerContext,
    handler: protocol.CommandHandler,
) !void {
    var line = std.ArrayList(u8).init(allocator);
    defer line.deinit();

    while (true) {
        line.clearRetainingCapacity();
        reader.streamUntilDelimiter(line.writer(), '\n', max_control_line) catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };
        try line.append('\n');

        const parsed = try parseControlLine(line.items);
        if (parsed.kind == .line) {
            try handler(ctx, line.items);
            continue;
        }

        if (parsed.payload_len > max_payload) return error.PayloadTooLarge;

        var frame = std.ArrayList(u8).init(allocator);
        defer frame.deinit();
        try frame.appendSlice(line.items);
        const start = frame.items.len;
        try frame.resize(start + parsed.payload_len + 2);
        try reader.readNoEof(frame.items[start .. start + parsed.payload_len + 2]);
        if (!std.mem.eql(u8, frame.items[frame.items.len - 2 ..], "\r\n")) return error.InvalidNatsPayloadTerminator;

        try handler(ctx, frame.items);
    }
}

pub fn parseControlLine(line_with_lf: []const u8) !ParsedControlLine {
    const line = std.mem.trimRight(u8, line_with_lf, "\r\n");
    if (line.len == 0) return error.EmptyNatsCommand;

    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
    const op = tokens.next() orelse return error.EmptyNatsCommand;

    if (asciiEq(op, "PUB") or asciiEq(op, "MSG")) {
        const len_token = lastToken(line) orelse return error.InvalidNatsCommand;
        return .{ .kind = .payload, .payload_len = try parseLen(len_token) };
    }

    if (asciiEq(op, "HPUB") or asciiEq(op, "HMSG")) {
        var count: usize = 0;
        var total_len_token: ?[]const u8 = null;
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        while (it.next()) |token| {
            count += 1;
            total_len_token = token;
        }
        if (count < 4) return error.InvalidNatsCommand;
        return .{ .kind = .payload, .payload_len = try parseLen(total_len_token.?) };
    }

    return .{ .kind = .line };
}

fn asciiEq(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

fn lastToken(line: []const u8) ?[]const u8 {
    var it = std.mem.tokenizeScalar(u8, line, ' ');
    var last: ?[]const u8 = null;
    while (it.next()) |token| last = token;
    return last;
}

fn parseLen(token: []const u8) !usize {
    return std.fmt.parseUnsigned(usize, token, 10) catch error.InvalidPayloadLength;
}

test "parse NATS payload commands" {
    try std.testing.expectEqual(@as(usize, 5), (try parseControlLine("PUB foo 5\r\n")).payload_len);
    try std.testing.expectEqual(@as(usize, 9), (try parseControlLine("HPUB foo 4 9\r\n")).payload_len);
    try std.testing.expectEqual(FrameKind.line, (try parseControlLine("PING\r\n")).kind);
}
