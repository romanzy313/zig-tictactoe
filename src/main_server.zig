const std = @import("std");
const Allocator = std.mem.Allocator;
const debug = std.debug;
const net = std.net;
const server_tcp = @import("server/tcp.zig");
const test_client = @import("server/test_client.zig");

// Define a struct for "global" data passed into your websocket handler
// This is whatever you want. You pass it to `listen` and the library will
// pass it back to your handler's `init`. For simple cases, this could be empty
const Context = struct {
    allocator: Allocator,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};

    defer {
        const check = gpa.deinit();

        if (check == .leak) {
            debug.print("THERE WAS A LEAK !!!1!\n", .{});
        }
    }

    const allocator = gpa.allocator();

    const port: u16 = 5432;
    const address = "0.0.0.0";
    const addr = try net.Address.parseIp4(address, port);

    var server = try server_tcp.GameServer.init(allocator, addr);
    defer server.deinit();

    for (0..5) |i| {
        const thread = try std.Thread.spawn(.{}, run_client, .{@as(u32, @intCast(i))});
        thread.detach();
    }

    try server.run_forever();
}

const log_client = std.log.scoped(.client);

fn run_client(id: u32) !void {
    const address = try net.Address.parseIp4("127.0.0.1", 5432);
    while (true) {
        std.time.sleep(1 * std.time.ns_per_s);

        const stream = try net.tcpConnectToAddress(address);
        defer stream.close();

        log_client.info("({d}) Connected to {}\n", .{ id, address });
        var writer = stream.writer();

        var msg_count: usize = 0;
        while (true) {
            msg_count += 1;
            std.time.sleep(50 * std.time.ns_per_ms);

            log_client.info("Sending '({d}) [{d}] hello zig\n'", .{ id, msg_count });
            writer.print("({d}) [{d}] hello zig\n", .{ id, msg_count }) catch |err| {
                log_client.err("({d}) [{d}] failed to send: {any}", .{ id, msg_count, err });
                return;
            };
        }
    }
}
