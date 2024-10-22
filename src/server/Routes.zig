const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const zap = @import("zap");
const logger = std.log.scoped(.routes);

const helpers = @import("helpers.zig");
const ai = @import("common").ai;
const uuid = @import("vendor").uuid;
const GameRepo = @import("game_repo.zig").GameRepo;
const GameInstance = @import("game_repo.zig").GameInstance;

allocator: Allocator,
gameRepo: *GameRepo,
hostname: []const u8,

// following this: https://github.com/zigzap/zap/blob/master/examples/simple_router/simple_router.zig
const Routes = @This();

pub fn init(allocator: Allocator, game_repo: *GameRepo, hostname: []const u8) Routes {
    return .{
        .allocator = allocator,
        .gameRepo = game_repo,
        .hostname = hostname,
    };
}

pub const StartGameReq = struct {
    // explicit value must be set to accept empty values
    // https://github.com/ziglang/zig/issues/21013
    ai: ?ai.Difficulty = null,
};
pub const StartGameRes = struct {
    gameId: []const u8, // can I hold this as binary values?
    playerId: []const u8,
    playerUrl: []const u8,
    anotherWay2: []const u8,
    anotherWay: []const u8,
    inviteUrl: ?[]const u8 = null,
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

    const temp = self.gameRepo.newGame() catch {
        req.setStatus(.internal_server_error);
        return req.sendBody("failed to create a new game") catch unreachable; // unreachable is nervewrecking
    };
    var inst = self.gameRepo.get(temp.gameId).?;

    // var inviteUrl: ?[]const u8 = null;

    // const hasOpponent = if (body.value.ai == null) true else false;
    // if (hasOpponent) {
    //     // also need to generate other player Id
    //     inviteUrl = inst.gameUrlForPlayerO(); // self.hostname ++

    // }

    // maybe its not my issue.
    // maybe its zap and whatever it does when dispatching a request:
    // .bound => |b| @call(.auto, @as(BoundHandler, @ptrFromInt(b.handler)), .{ @as(*anyopaque, @ptrFromInt(b.instance)), r }),

    const same_thing_away = inst.gameUrlForPlayerX();
    const const_here = "/game?gameId=" ++ inst.gameId.format_uuid() ++ "&playerId=" ++ inst.playerX.id.format_uuid();

    var buf: [13 + 36 + 10 + 36]u8 = undefined;
    std.debug.print("SELF IS 111 \"{any}\"\n", .{self});
    const same_thing_away2_works: []const u8 = std.fmt.bufPrint(&buf, "/game?gameId={s}&playerId={s}", .{
        inst.gameId,
        inst.playerX.id,
    }) catch |err| {
        std.debug.print("failed to buffprint !!!! ERR: {any}\n", .{err});

        return;
    };

    // const same_thing_away = inst.gameUrlForPlayerXComptime();
    std.debug.print("VALUEEE:::\n1) {s}\n2) {s} \n", .{ const_here, same_thing_away });

    // encode the response
    const res: []const u8 = json.stringifyAlloc(
        self.allocator,
        StartGameRes{
            .gameId = &inst.gameId.format_uuid(),
            .playerId = &inst.playerX.id.format_uuid(),
            // .playerUrl = inst.gameUrlForPlayerX(),
            // this returns a "string"
            .playerUrl = const_here,
            .anotherWay2 = same_thing_away2_works,
            .anotherWay = same_thing_away,
            // this returns a byte array...
            // .inviteUrl = same_thing_away,
            // .inviteUrl = inviteUrl,
        },
        .{
            .emit_strings_as_arrays = false,
            .emit_null_optional_fields = false,
        },
    ) catch return; // does this mean it wont return anything?

    // TODO: add this game to the game repo

    // req.setStatus(.temporary_redirect);
    // req.setHeader("Location", fullUrl) catch return;
    req.sendJson(res) catch return;
}

pub const GetGameDataReq = struct {
    gameId: []const u8,
};

pub fn getGameData(self: *Routes, req: zap.Request) void {
    const body = helpers.parseBodyJson(GetGameDataReq, self.allocator, &req, .{}) catch |err| {
        // req.setStatus(.bad_request);
        // req.sendJson("{ \"ok\": false }") catch return;
        return req.sendError(err, if (@errorReturnTrace()) |t| t.* else null, 500);
    };
    defer body.deinit();

    const game_id_as_uuid = uuid.UUID.parse(body.value.gameId) catch |err| {
        return req.sendError(err, null, 502);
    };

    const inst = self.gameRepo.get(game_id_as_uuid);

    if (inst == null) {
        return req.sendBody("instance with id" ++ game_id_as_uuid.format_uuid() ++ " not found!") catch return;
    }

    const res = json.stringifyAlloc(self.allocator, inst.?, .{}) catch return;

    req.sendJson(res) catch return;
}
