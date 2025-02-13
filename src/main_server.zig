const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const debug = std.debug;
const websocket = @import("websocket");
const Conn = websocket.Conn;
const Message = websocket.Message;
const Handshake = websocket.Handshake;

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

    // this is the instance of your "global" struct to pass into your handlers
    var context = Context{
        .allocator = allocator,
    };

    const port: u16 = 5432;
    const address = "0.0.0.0";

    log.info("server will listen on {s}:{d}", .{ address, port });

    try websocket.listen(Handler, allocator, &context, .{
        .port = port,
        .max_headers = 10,
        .address = address,
    });
}

const Handler = struct {
    conn: *Conn,
    userId: []const u8, // just for testing
    context: *Context,

    pub fn init(handshake: Handshake, conn: *Conn, context: *Context) !Handler {
        // `h` contains the initial websocket "handshake" request
        // It can be used to apply application-specific logic to verify / allow
        // the connection (e.g. valid url, query string parameters, or headers)

        log.info("accepting connection from {s}", .{handshake.url});

        const token = handshake.headers.get("authorization") orelse {
            return error.NotAuthorized;
        };

        // a copy must be made as per docs

        // the incoming request could be /new for new game
        // join/:code for the join game connection

        return Handler{
            .conn = conn,
            .userId = try context.allocator.dupe(u8, token),
            .context = context,
        };
    }

    // optional hook that, if present, will be called after initialization is complete
    pub fn afterInit(_: *Handler) !void {}

    pub fn handle(self: *Handler, message: Message) !void {
        const data = message.data;

        debug.print("data incoming: {any}\n", .{message.data});
        log.info("got message: {any}", .{message.data});
        try self.conn.write(self.userId);
        try self.conn.write(": ");
        try self.conn.write(data); // echo the message back
    }

    // called whenever the connection is closed, can do some cleanup in here
    pub fn close(_: *Handler) void {}
};
