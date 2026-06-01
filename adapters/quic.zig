const std = @import("std");
const protocol = @import("protocol.zig");
const tcp = @import("tcp.zig");

pub const Options = struct {
    allocator: std.mem.Allocator,
    mtls: protocol.MtlsOptions,
    alpn: []const u8 = "nats-quic/1",
};

pub const Stream = struct {
    reader: std.net.Stream.Reader,
    writer: std.net.Stream.Writer,
};

/// QUIC transport adapter boundary.
///
/// The QUIC implementation that owns UDP, TLS 1.3, congestion control and stream
/// multiplexing hands each accepted bidirectional stream to this adapter. From
/// this point on the adapter treats the stream exactly like the TCP NATS socket:
/// it parses complete NATS wire frames and invokes the same command handler used
/// by the TCP path. No command is renamed or translated.
pub fn deliverBidirectionalStream(
    allocator: std.mem.Allocator,
    quic_reader: anytype,
    handler_ctx: *protocol.HandlerContext,
    handler: protocol.CommandHandler,
) !void {
    handler_ctx.protocol = .quic;
    try tcp.deliverNatsFrames(allocator, quic_reader, handler_ctx, handler);
}

pub fn assertMtls(options: Options) !void {
    if (options.mtls.ca_cert_path.len == 0 or options.mtls.cert_path.len == 0 or options.mtls.key_path.len == 0) {
        return error.MtlsRequiredForQuic;
    }
}
