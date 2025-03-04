const std = @import("std");
const log = std.log;
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
    const thread = try std.Thread.spawn(.{}, run_clients, .{});
    _ = thread;
    try server_tcp.createServer(allocator, address, port);
}

fn run_clients() void {
    while (true) {
        std.time.sleep(1 * std.time.ns_per_s);
        test_client.runClient() catch |err| {
            debug.print("client error: {any}\n", .{err});
        };
    }
}
