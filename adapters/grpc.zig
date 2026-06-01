const std = @import("std");
const protocol = @import("protocol.zig");

pub const content_type = "application/grpc+nats";
pub const service = "nats.adapter.v1.CommandChannel";
pub const bidi_method = "Subscribe";

pub const Options = struct {
    mtls: protocol.MtlsOptions,
    max_message_size: usize = 1024 * 1024 * 64,
};

/// Delivers a gRPC bidirectional-stream request body to the NATS command
/// handler. The HTTP/2 server layer owns header compression, flow control and
/// DATA-frame reassembly; this adapter owns the gRPC message envelope and keeps
/// the payload as raw NATS protocol bytes.
pub fn deliverGrpcMessages(
    allocator: std.mem.Allocator,
    reader: anytype,
    handler_ctx: *protocol.HandlerContext,
    handler: protocol.CommandHandler,
    options: Options,
) !void {
    handler_ctx.protocol = .grpc;

    while (true) {
        var header: [5]u8 = undefined;
        reader.readNoEof(&header) catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };

        if (header[0] != 0) return error.CompressedGrpcMessageNotSupported;
        const len = std.mem.readInt(u32, header[1..5], .big);
        if (len > options.max_message_size) return error.GrpcMessageTooLarge;

        const command = try allocator.alloc(u8, len);
        defer allocator.free(command);
        try reader.readNoEof(command);
        try handler(handler_ctx, command);
    }
}

pub fn writeGrpcMessage(writer: anytype, command: []const u8) !void {
    if (command.len > std.math.maxInt(u32)) return error.GrpcMessageTooLarge;
    var header: [5]u8 = .{ 0, 0, 0, 0, 0 };
    std.mem.writeInt(u32, header[1..5], @intCast(command.len), .big);
    try writer.writeAll(&header);
    try writer.writeAll(command);
}
