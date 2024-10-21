const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const zap = @import("zap");

const ai = @import("common").ai;
const uuid = @import("vendor").uuid;

const logger = std.log.scoped(.routes);
const helpers = @import("helpers.zig");

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
    // explicit value must be set to accept empty values
    // https://github.com/ziglang/zig/issues/21013
    ai: ?ai.Difficulty = null,
};
pub const StartGameRes = struct {
    gameId: []const u8,
    playerId: []const u8,
    playerUrl: []const u8,
    inviteUrl: ?[]const u8,
};

// I think this must be void, no error should be returned
// or else the application crashes!
pub fn newGame(self: *Routes, req: zap.Request) void {

    // can only use JSON speicifc method
    const body = helpers.parseBodyJson(StartGameReq, self.allocator, &req, .{}) catch |err| {
        // req.setStatus(.bad_request);
        // req.sendJson("{ \"ok\": false }") catch return;
        return req.sendError(err, if (@errorReturnTrace()) |t| t.* else null, 500);
    };
    defer body.deinit();

    logger.info("requested to start a new game with options: \"{any}\"", .{body.value});

    const gameId = uuid.newV4().format_uuid();
    const playerId = uuid.newV4().format_uuid(); // create a new temporary player
    const playerGameUrl = "/game?gameId=" ++ gameId ++ "&playerId=" ++ playerId;
    var inviteUrl: ?[]const u8 = null;

    const hasOpponent = if (body.value.ai == null) true else false;
    if (hasOpponent) {
        // also need to generate other player Id
        const otherPlayerId = uuid.newV4().format_uuid(); // create a new temporary player
        inviteUrl = "/game?gameId=" ++ gameId ++ "&playerId=" ++ otherPlayerId; // self.hostname ++

    }

    // encode the response
    const res: []const u8 = json.stringifyAlloc(
        self.allocator,
        StartGameRes{
            .gameId = &gameId,
            .playerId = &playerId,
            .playerUrl = playerGameUrl,
            // .inviteUrl = "",
            .inviteUrl = inviteUrl,
        },
        .{},
    ) catch return; // does this mean it wont return anything?

    // TODO: add this game to the game repo

    // req.setStatus(.temporary_redirect);
    // req.setHeader("Location", fullUrl) catch return;
    req.sendJson(res) catch return;
}
