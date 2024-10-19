const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const zap = @import("zap");

const ai = @import("common").ai;
const uuid = @import("vendor").uuid;

const logger = std.log.scoped(.routes);

allocator: Allocator,
hostname: []const u8,

// following this: https://github.com/zigzap/zap/blob/master/examples/simple_router/simple_router.zig
const Routes = @This();

pub fn init(allocator: Allocator, hostname: []const u8) Routes {
    return .{
        .allocator = allocator,
        .hostname = hostname,
    };
}

pub const StartGameReq = struct {
    ai: ?ai.Difficulty,
};
pub const StartGameRes = struct { gameId: []const u8, url: []const u8 };

// I think this must be void, no error should be returned
// or else the application crashes!
pub fn newGame(self: *Routes, req: zap.Request) void {
    logger.info("requested to start a new game", .{});

    req.parseBody() catch |err| {
        logger.err("Parse Body error: {any}. Expected if body is empty", .{err});
        return;
    };

    // huh? how is this []const u8?
    if (req.body) |body| {
        logger.info("Body length is {any}\n", .{body.len});

        // catch unreachable will spam the console and CRASH the process
        // const parsed = std.json.parseFromSlice(StartGameReq, self.allocator, body, .{}) catch unreachable;

        const parsed = std.json.parseFromSlice(StartGameReq, self.allocator, body, .{}) catch |err| {
            logger.err("could not parse the json: {any}", .{err});
            // can return a stack trace, but its not nice...
            return req.sendError(err, if (@errorReturnTrace()) |t| t.* else null, 500);
            // req.sendJson("cannot parse the input") catch return;
            // return;
        };
        defer parsed.deinit();

        logger.info("parsed request is: \"{any}\" \n", .{parsed.value});

        const gameId = uuid.newV4().format_uuid();

        const fullUrl = "/game/" ++ gameId; // self.hostname ++

        // encode the response
        const res: []const u8 = json.stringifyAlloc(
            self.allocator,
            StartGameRes{ .gameId = &gameId, .url = fullUrl },
            .{},
        ) catch return; // does this mean it wont return anything?

        // req.setStatus(.temporary_redirect);
        // req.setHeader("Location", fullUrl) catch return;
        req.sendJson(res) catch return;

        return;
    }

    // this is bad! i want to go on a happy path down, not nest it
    req.setStatus(.bad_request);
    req.sendJson("{ \"ok\": false }") catch return;
}
