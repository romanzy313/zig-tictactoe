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
    inviteUrl: ?[]const u8 = null,
};

// I think this must be void, no error should be returned
// or else the application crashes!
pub fn newGame(self: *Routes, req: zap.Request) void {
    const body = helpers.parseBodyJson(StartGameReq, self.allocator, &req, .{}) catch |err| {
        return req.sendError(err, if (@errorReturnTrace()) |t| t.* else null, 500);
    };
    defer body.deinit();

    logger.info("requested to start a new game with options: \"{any}\"", .{body.value});

    var game = self.gameRepo.newGame() catch {
        req.setStatus(.internal_server_error);
        return req.sendBody("failed to create a new game") catch unreachable; // unreachable is nervewrecking
    };
    // this needs to deinit it... again
    const player_url = game.gameUrlForPlayerX(self.allocator) catch unreachable;
    defer self.gameRepo.allocator.free(player_url);
    const invite_url = game.gameUrlForPlayerO(self.allocator) catch unreachable;
    defer self.gameRepo.allocator.free(invite_url);

    // encode the response
    const res: []const u8 = json.stringifyAlloc(
        self.allocator,
        StartGameRes{
            .gameId = &game.gameId.format_uuid(),
            .playerId = &game.playerX.id.format_uuid(),
            .playerUrl = player_url,
            .inviteUrl = invite_url,
        },
        .{
            .emit_strings_as_arrays = false,
            .emit_null_optional_fields = false,
        },
    ) catch return; // does this mean it wont return anything?
    defer self.allocator.free(res);

    req.sendJson(res) catch return;
}

pub const GetGameDataReq = struct {
    gameId: []const u8,
};

pub fn getGame(self: *Routes, req: zap.Request) void {
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
    defer self.allocator.free(res);

    req.sendJson(res) catch return;
}

pub fn getAllgames(self: *Routes, req: zap.Request) void {
    // self.gameRepo.games.

    const allOwned = self.gameRepo.getAll() catch |err| {
        return req.sendError(err, if (@errorReturnTrace()) |t| t.* else null, 500);
    };
    defer self.gameRepo.allocator.free(allOwned); // ugly but works

    const res = json.stringifyAlloc(self.allocator, allOwned, .{}) catch return;
    defer self.allocator.free(res);

    req.sendJson(res) catch return;
}
