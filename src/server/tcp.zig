const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const debug = std.debug;
const net = std.net;
const Server = net.Server;

// following
// https://cookbook.ziglang.cc/04-01-tcp-server.html
// and
// https://www.openmymind.net/TCP-Server-In-Zig-Part-4-Multithreading/
// if port is 0 it will be randomly assigned
// i think this is TCP?
pub fn createServer(allocator: Allocator, host: []const u8, port: u16) !void {
    _ = allocator;

    // const addr = net.Address.initIp4(host, port);
    const addr = try net.Address.parseIp4(host, port);

    var server = try addr.listen(.{
        .reuse_address = true,
        .reuse_port = false, // sanity check
    });
    defer server.deinit();

    const listen_addr = server.listen_address;
    _ = listen_addr; // return this to the caller, so that during tests this random port can be connected to

    debug.print("TCP server listening on {any}\n", .{addr});

    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    while (true) {
        var client = try server.accept();
        defer client.stream.close();

        client.stream.reader().any().streamUntilDelimiter(fbs.writer(), '\n', 1024) catch |err| {
            // stream was too long probably

            if (err != error.EndOfStream) {
                std.debug.print("client {any} gave troubles: {any}\n", .{ client.address, err });
                break; // terminate the connection
            }
        };
        const message = fbs.getWritten();
        debug.print("{any} says {s}\n", .{ client.address, message });
        fbs.reset();
    }

    // i need to create a different thread for each one of the client
    // also i need to store the rooms implemented there

}

const Client = struct {
    conn: Server.Connection,

    fn handle(self: *Client) !void {
        const conn = self.conn;
        defer conn.stream.close();

        debug.print("client {any} connected\n", .{self.address});

        // maximum message size is 1kb
        var buf: [1024]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);

        // fbs.reader().readUntilDelimiter(buf: []u8, delimiter: u8)

        while (true) {
            // its depricated, but I got no idea how to undepricate it
            //
            //
            fbs.reader().any().streamUntilDelimiter(fbs.writer(), '\n', 1024) catch |err| {
                // stream was too long probably
                // terminate the connection
                std.debug.print("client {any} gave troubles: {any}\n", .{ self.client.address, err });
                return;
            };

            const raw_msg = fbs.getWritten();

            std.debug.print("Got: {s}\n", .{raw_msg});

            // handle the message here

            // reset the stream
            fbs.reset();
        }
    }
};

// I need to create a server, it needs to have various implementations
