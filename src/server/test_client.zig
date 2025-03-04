const std = @import("std");
const net = std.net;
const print = std.debug.print;

pub fn runClient() !void {
    const peer = try net.Address.parseIp4("127.0.0.1", 5432);
    // Connect to peer
    const stream = try net.tcpConnectToAddress(peer);
    defer stream.close();
    print("Connecting to {}\n", .{peer});

    // Sending data to peer
    const data = "hello zig\n";
    var writer = stream.writer();
    const size = try writer.write(data);
    print("Sending '{s}' to peer, total written: {d} bytes\n", .{ data, size });
    // Or just using `writer.writeAll`
    // try writer.writeAll("hello zig");
}
