const std = @import("std");
const protocol = @import("protocol.zig");

pub const nats_subprotocol = "nats.v1";
pub const max_frame_payload = 1024 * 1024 * 64;

pub const Options = struct {
    mtls: protocol.MtlsOptions,
    require_subprotocol: bool = true,
};

pub fn acceptHandshake(allocator: std.mem.Allocator, reader: anytype, writer: anytype, options: Options) !void {
    var key: ?[]u8 = null;
    defer if (key) |value| allocator.free(value);
    var saw_subprotocol = !options.require_subprotocol;

    while (true) {
        const line = try reader.readUntilDelimiterAlloc(allocator, '\n', 8192);
        defer allocator.free(line);
        const trimmed = std.mem.trimRight(u8, line, "\r\n");
        if (trimmed.len == 0) break;
        if (startsWithIgnoreCase(trimmed, "Sec-WebSocket-Key:")) {
            key = try allocator.dupe(u8, std.mem.trim(u8, trimmed[18..], " \t"));
        } else if (startsWithIgnoreCase(trimmed, "Sec-WebSocket-Protocol:")) {
            var protocols = std.mem.tokenizeScalar(u8, trimmed[23..], ',');
            while (protocols.next()) |candidate| {
                if (std.mem.eql(u8, std.mem.trim(u8, candidate, " \t"), nats_subprotocol)) saw_subprotocol = true;
            }
        }
    }

    if (key == null) return error.MissingWebSocketKey;
    if (!saw_subprotocol) return error.MissingNatsWebSocketSubprotocol;

    const accept_src = try std.mem.concat(allocator, u8, &.{ key.?, "258EAFA5-E914-47DA-95CA-C5AB0DC85B11" });
    defer allocator.free(accept_src);
    var digest: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(accept_src, &digest, .{});
    var accept_value: [std.base64.standard.Encoder.calcSize(20)]u8 = undefined;
    _ = std.base64.standard.Encoder.encode(&accept_value, &digest);

    try writer.print(
        "HTTP/1.1 101 Switching Protocols\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Accept: {s}\r\n" ++
        "Sec-WebSocket-Protocol: " ++ nats_subprotocol ++ "\r\n" ++
        "\r\n",
        .{accept_value},
    );
}

pub fn deliverFrames(
    allocator: std.mem.Allocator,
    reader: anytype,
    handler_ctx: *protocol.HandlerContext,
    handler: protocol.CommandHandler,
) !void {
    handler_ctx.protocol = .websocket;

    while (true) {
        const frame = readFrame(allocator, reader) catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };
        defer allocator.free(frame.payload);

        switch (frame.opcode) {
            .binary, .text => try handler(handler_ctx, frame.payload),
            .close => return,
            .ping, .pong => {},
        }
    }
}

const Opcode = enum { text, binary, close, ping, pong };
const Frame = struct { opcode: Opcode, payload: []u8 };

fn startsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    return haystack.len >= needle.len and
        std.ascii.eqlIgnoreCase(haystack[0..needle.len], needle);
}

fn readFrame(allocator: std.mem.Allocator, reader: anytype) !Frame {
    var head: [2]u8 = undefined;
    try reader.readNoEof(&head);
    const opcode: Opcode = switch (head[0] & 0x0f) {
        0x1 => .text,
        0x2 => .binary,
        0x8 => .close,
        0x9 => .ping,
        0xa => .pong,
        else => return error.UnsupportedWebSocketOpcode,
    };
    const masked = (head[1] & 0x80) != 0;
    var len: u64 = head[1] & 0x7f;
    if (len == 126) {
        var ext: [2]u8 = undefined;
        try reader.readNoEof(&ext);
        len = std.mem.readInt(u16, &ext, .big);
    } else if (len == 127) {
        var ext: [8]u8 = undefined;
        try reader.readNoEof(&ext);
        len = std.mem.readInt(u64, &ext, .big);
    }
    if (len > max_frame_payload) return error.WebSocketFrameTooLarge;

    var mask: [4]u8 = .{ 0, 0, 0, 0 };
    if (masked) try reader.readNoEof(&mask);

    const payload = try allocator.alloc(u8, @intCast(len));
    errdefer allocator.free(payload);
    try reader.readNoEof(payload);
    if (masked) {
        for (payload, 0..) |*byte, i| byte.* ^= mask[i % 4];
    }
    return .{ .opcode = opcode, .payload = payload };
}
