const std = @import("std");

pub const Protocol = enum {
    tcp,
    quic,
    grpc,
    websocket,
};

pub const HandlerContext = struct {
    allocator: std.mem.Allocator,
    protocol: Protocol,
    subscriber_id: ?[]const u8 = null,
    peer: ?[]const u8 = null,
};

pub const CommandHandler = *const fn (ctx: *HandlerContext, command: []const u8) anyerror!void;

pub const AdapterOptions = struct {
    protocol: Protocol,
    listen_host: []const u8 = "0.0.0.0",
    listen_port: u16,
    nats_host: []const u8 = "127.0.0.1",
    nats_port: u16 = 4222,
    mtls: ?MtlsOptions = null,
};

pub const MtlsOptions = struct {
    ca_cert_path: []const u8,
    ca_key_path: []const u8,
    cert_path: []const u8,
    key_path: []const u8,
    verify_peer: bool = true,
};

pub fn modeFromString(mode: []const u8) !Protocol {
    if (std.ascii.eqlIgnoreCase(mode, "TCP")) return .tcp;
    if (std.ascii.eqlIgnoreCase(mode, "QUIC")) return .quic;
    if (std.ascii.eqlIgnoreCase(mode, "GRPC") or std.ascii.eqlIgnoreCase(mode, "gRPC")) return .grpc;
    if (std.ascii.eqlIgnoreCase(mode, "WEBSOCKET") or std.ascii.eqlIgnoreCase(mode, "WS")) return .websocket;
    return error.UnsupportedProtocolMode;
}

test "modeFromString accepts requested adapter modes" {
    try std.testing.expectEqual(Protocol.quic, try modeFromString("QUIC"));
    try std.testing.expectEqual(Protocol.grpc, try modeFromString("gRPC"));
    try std.testing.expectEqual(Protocol.websocket, try modeFromString("websocket"));
}
