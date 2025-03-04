const std = @import("std");
const Allocator = std.mem.Allocator;
const debug = std.debug;
const net = std.net;
const Server = net.Server;

const log = std.log.scoped(.server);

// following
// https://cookbook.ziglang.cc/04-01-tcp-server.html
// and
// https://www.openmymind.net/TCP-Server-In-Zig-Part-4-Multithreading/
// if port is 0 it will be randomly assigned
// i think this is TCP?
pub fn createServer(allocator: Allocator, addr: net.Address) !void {
    _ = allocator;

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

// i must create an arena allocator to each client?

pub const GameServer = struct {
    allocator: Allocator,

    server: net.Server,
    listen_addr: net.Address,

    running: bool = true,

    pub fn init(allocator: Allocator,   addr: net.Address) !GameServer {
        const server = try addr.listen(.{
            .reuse_address = true,
            .reuse_port = false, // sanity check
        });
        const listen_addr = server.listen_address;

        log.info("listening at {any}", .{listen_addr});

        return .{
            .allocator = allocator,
            .server = server,
            .listen_addr = listen_addr,
        };
    }

    pub fn stop(self: *GameServer) void {
        self.running = false;

        // also will need to wait until all threads are cleaned up or smth
        // this will be a challenge once tests are created
    }

    pub fn deinit(self: *GameServer) void {
        // cleanup all clients
        log.info("shutting down", .{});

        defer self.server.deinit();
    }

    // runforever type of thing
    pub fn run_forever(self: *GameServer) !void {
        while (self.running) {
            const client = try self.server.accept();
            log.info("new client accepted {any}", .{client.address});

            const thread = try std.Thread.spawn(.{}, GameServer.handle_client, .{client});
            thread.detach();
        }
    }

    /// each client is handled in its own thread
    pub fn handle_client(client: Server.Connection) void {
        defer client.stream.close();
        log.info("new client thread created {any}", .{client.address});

        // maximum message size is 1kb
        var buf: [1024]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);

        var msg_count: usize = 0;

        // fbs.reader().readUntilDelimiter(buf: []u8, delimiter: u8)

        while (true) {
            msg_count += 1;
            client.stream.reader().any().streamUntilDelimiter(fbs.writer(), '\n', 1024) catch |err| {
                // stream was too long probably
                // terminate the connection

                switch (err) {
                    // ignored errors, as there are lots of empty values
                    error.EndOfStream => {
                        // const pos = try fbs.getPos();
                        // if (pos == 0) {
                        //     continue;
                        // }
                        log.info("client {any} actual end of stream. pos: {d}!", .{ client.address, fbs.pos });
                    },
                    else => {
                        log.info("client {any} gave troubles: {any}", .{ client.address, err });
                        return;
                    },
                }
            };

            const read = fbs.pos;

            if (read > 0) {
                const raw_msg = fbs.getWritten();

                // handle the message here
                log.info("[{d}] client message: {s}", .{ msg_count, raw_msg });

                // reset the stream
                fbs.reset();
            }
        }
    }

    // running this must be done in its own thread
    //
};
