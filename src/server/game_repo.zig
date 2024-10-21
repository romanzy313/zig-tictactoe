const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const common = @import("common");
const game = common.game;
const State = common.game.State;
const uuid = @import("vendor").uuid;

pub const GameInstance = struct {
    game_id: uuid.UUID, // this is a fixed size though...
    player_x: game.AnyPlayer,
    player_o: game.AnyPlayer,
    state: State,
    // i need to embed the game.State here...
    // so it must be common, I must register it under a common "module", via build.zig

    // dont forget to deinit state!
    // any player could be an AI though...
    // and AI MUST be ran on the outside machine for "proper learning experience"
    // AI MUST be a stateful object which can be accessed by network
    pub fn initRandom(allocator: Allocator) !GameInstance {
        const state = try game.State.init(allocator, 3);
        return .{
            .game_id = uuid.newV4(),
            .player_x = game.AnyPlayer.random(.human), // this needs to be determined
            .player_o = game.AnyPlayer.random(.ai), // ai id is created here, but ai must be made separately...
            .state = state,
        };
    }

    pub fn deinit(self: GameInstance, allocator: Allocator) void {
        // allocator.free(self.state);
        self.state.deinit(allocator);
    }

    pub fn gameUrlForPlayerX(self: GameInstance) []const u8 {
        return "/game?gameId=" ++ self.game_id ++ "&playerId=" ++ self.player_x;
    }
    pub fn gameUrlForPlayerY(self: GameInstance) []const u8 {
        return "/game?gameId=" ++ self.game_id ++ "&playerId=" ++ self.player_y;
    }
    pub fn gameUrlForPlayer(self: GameInstance, player: game.PlayerKind) []const u8 {
        return switch (player) {
            .X => self.gameUrlForPlayerX(),
            .Y => self.gameUrlForPlayerY(),
        };
    }
};

pub const GameRepo = struct {
    allocator: Allocator,
    // games: std.StringHashMap(GameInstance),
    games: std.AutoHashMap(uuid.UUID, GameInstance),

    pub fn init(allocator: Allocator) GameRepo {
        const games = std.AutoHashMap(uuid.UUID, GameInstance).init(allocator);
        return .{
            .allocator = allocator,
            .games = games,
        };
    }

    pub fn deinit(self: *GameRepo) void {
        // remove all games first!!!
        // this is not sufficient, because each allocated state needs deinitialization
        // self.games.clearAndFree();
        var iter = self.games.valueIterator();
        while (iter.next()) |entry| {
            entry.deinit(self.allocator);
        }
        self.games.deinit();
    }

    /// creates a new game and returns it
    /// memory is freed automatically on delete()
    pub fn newGame(self: *GameRepo) !GameInstance {
        const game_instance = try GameInstance.initRandom(self.allocator);

        try self.games.put(game_instance.game_id, game_instance);

        return game_instance;
    }

    pub fn get(self: *GameRepo, game_id: uuid.UUID) !GameInstance {
        return try self.games.get(game_id);
    }

    pub fn delete(self: *GameRepo, game_id: uuid.UUID) bool {
        const val = self.games.get(game_id);

        // std.debug.print("???? game_id={s}, val={any} \n", .{ game_id, val });

        if (val == null) {
            return false;
        }

        // dont forget to free the state!
        // this is awkward...
        defer val.?.deinit(self.allocator);

        const ok = self.games.remove(game_id);

        // if (ok) {
        //     val.?.deinit(self.allocator);
        // }

        return ok;
    }
};

test "adding and removing games" {
    const testing_allocator = testing.allocator;

    var r = GameRepo.init(testing_allocator);
    defer r.deinit();

    const g = try r.newGame();

    try testing.expectEqual(1, r.games.count());

    const ok = r.delete(g.game_id);

    try testing.expect(ok);
}

test "autocleanup on deinit" {
    const testing_allocator = testing.allocator;

    var r = GameRepo.init(testing_allocator);

    _ = try r.newGame();

    // std.debug.print("GOT GAME {s}\n", .{g.game_id});

    try testing.expectEqual(1, r.games.count());

    // expect no leaks
    r.deinit();
}
