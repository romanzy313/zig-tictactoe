const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const zap = @import("zap");

const ai = @import("ai");
const uuid = @import("vendor").uuid;

const logger = std.log.scoped(.routes);

allocator: Allocator,

// following this: https://github.com/zigzap/zap/blob/master/examples/simple_router/simple_router.zig
const Routes = @This();

pub fn init(allocator: Allocator) Routes {
    return .{
        .allocator = allocator,
    };
}

pub const StartGameReq = struct {
    ai: ?ai.Difficulty,
};
pub const StartGameRes = struct { gameId: []const u8 };

// halfassed random number generator:
// fn getRandomId() ![]u8 {
//     const rand = std.crypto.random;
//     const val = rand.int(u32);
//     var buf: [256]u8 = undefined;

//     return try std.fmt.bufPrint(&buf, "{}", .{val});
// }

// I think this must be void, no error should be returned
// or else the application crashes?
pub fn newGame(self: *Routes, req: zap.Request) void {
    logger.info("requested to start a new game", .{});

    req.parseBody() catch |err| {
        logger.err("Parse Body error: {any}. Expected if body is empty", .{err});
    };

    // huh? how is this []const u8?
    if (req.body) |body| {
        logger.info("Body length is {any}\n", .{body.len});

        const parsed = std.json.parseFromSlice(StartGameReq, self.allocator, body, .{}) catch |err| {
            logger.err("could not parse the json: {any}", .{err});
            return;
        };
        defer parsed.deinit();

        logger.info("parsed request is: \"{any}\" \n", .{parsed.value});

        const gameId = uuid.newV4();

        // encode the response
        const res: []const u8 = json.stringifyAlloc(self.allocator, StartGameRes{
            .gameId = &gameId.format_uuid(),
        }, .{}) catch return; // does this mean it wont return anything?

        req.sendJson(res) catch return;

        return;
    }

    // this is bad! i want to go on a happy path down, not nest it
    req.setStatus(.bad_request);
    req.sendJson("{ \"ok\": false }") catch return;
}
