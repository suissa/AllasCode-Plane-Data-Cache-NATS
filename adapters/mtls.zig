const std = @import("std");

pub const SubscriberRegistration = struct {
    agent_id: []const u8,
    subject: []const u8,
    output_dir: []const u8,
    ca_common_name: []const u8 = "AllasCode Plane Data Cache Agent CA",
    days_valid: u16 = 397,
};

pub const SubscriberMtlsMaterial = struct {
    ca_cert_path: []u8,
    cert_path: []u8,
    key_path: []u8,
};

pub fn registerSubscriberMtls(
    allocator: std.mem.Allocator,
    registration: SubscriberRegistration,
) !SubscriberMtlsMaterial {
    try std.fs.cwd().makePath(registration.output_dir);

    const ca_key_path = try std.fs.path.join(allocator, &.{ registration.output_dir, "agent-ca.key" });
    defer allocator.free(ca_key_path);
    const ca_cert_path = try std.fs.path.join(allocator, &.{ registration.output_dir, "agent-ca.crt" });

    const key_name = try safeFileName(allocator, registration.agent_id, ".key");
    defer allocator.free(key_name);
    const csr_name = try safeFileName(allocator, registration.agent_id, ".csr");
    defer allocator.free(csr_name);
    const cert_name = try safeFileName(allocator, registration.agent_id, ".crt");
    defer allocator.free(cert_name);
    const ext_name = try safeFileName(allocator, registration.agent_id, ".ext");
    defer allocator.free(ext_name);

    const subscriber_key_path = try std.fs.path.join(allocator, &.{ registration.output_dir, key_name });
    const subscriber_csr_path = try std.fs.path.join(allocator, &.{ registration.output_dir, csr_name });
    defer allocator.free(subscriber_csr_path);
    const subscriber_cert_path = try std.fs.path.join(allocator, &.{ registration.output_dir, cert_name });
    const ext_path = try std.fs.path.join(allocator, &.{ registration.output_dir, ext_name });
    defer allocator.free(ext_path);

    if (!exists(ca_key_path) or !exists(ca_cert_path)) {
        const ca_subject = try std.fmt.allocPrint(allocator, "/CN={s}", .{registration.ca_common_name});
        defer allocator.free(ca_subject);
        try run(&.{ "openssl", "genpkey", "-algorithm", "Ed25519", "-out", ca_key_path });
        try run(&.{ "openssl", "req", "-new", "-x509", "-key", ca_key_path, "-out", ca_cert_path, "-days", "3650", "-subj", ca_subject });
    }

    const subscriber_subject = try std.fmt.allocPrint(allocator, "/CN={s}", .{registration.agent_id});
    defer allocator.free(subscriber_subject);
    const days = try std.fmt.allocPrint(allocator, "{}", .{registration.days_valid});
    defer allocator.free(days);

    try run(&.{ "openssl", "genpkey", "-algorithm", "Ed25519", "-out", subscriber_key_path });
    try run(&.{ "openssl", "req", "-new", "-key", subscriber_key_path, "-out", subscriber_csr_path, "-subj", subscriber_subject });
    try writeSubscriberExtensions(ext_path, registration.agent_id, registration.subject);
    try run(&.{ "openssl", "x509", "-req", "-in", subscriber_csr_path, "-CA", ca_cert_path, "-CAkey", ca_key_path, "-CAcreateserial", "-out", subscriber_cert_path, "-days", days, "-extfile", ext_path });

    return .{
        .ca_cert_path = ca_cert_path,
        .cert_path = subscriber_cert_path,
        .key_path = subscriber_key_path,
    };
}

fn safeFileName(allocator: std.mem.Allocator, input: []const u8, suffix: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    for (input) |c| {
        try out.append(if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_') c else '_');
    }
    try out.appendSlice(suffix);
    return out.toOwnedSlice();
}

fn writeSubscriberExtensions(path: []const u8, agent_id: []const u8, subject: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writer().print(
        \\basicConstraints=CA:FALSE
        \\keyUsage=digitalSignature
        \\extendedKeyUsage=clientAuth,serverAuth
        \\subjectAltName=URI:agent://{s},URI:nats-subject://{s}
        \\
    , .{ agent_id, subject });
}

fn exists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn run(argv: []const []const u8) !void {
    var child = std.process.Child.init(argv, std.heap.page_allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    const result = try child.spawnAndWait();
    switch (result) {
        .Exited => |code| if (code != 0) return error.OpenSslFailed,
        else => return error.OpenSslFailed,
    }
}
