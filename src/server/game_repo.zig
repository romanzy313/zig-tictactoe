const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const common = @import("common");
const game = common.game;
const State = common.game.State;
const uuid = @import("vendor").uuid;

const Mutex = std.Thread.Mutex;

// FIXME: this should always be referenced by a pointer
// because the amount of data stored is huge!
// idk what goes on behind the hood now...
pub const GameInstance = struct {
    mutex: Mutex,
    gameId: uuid.UUID, // this is a fixed size though...
    playerX: game.AnyPlayer,
    playerO: game.AnyPlayer,
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
            .mutex = Mutex{},
            .gameId = uuid.newV4(),
            .playerX = game.AnyPlayer.random(.human), // this needs to be determined
            .playerO = game.AnyPlayer.random(.ai), // ai id is created here, but ai must be made separately...
            .state = state,
        };
    }

    pub fn deinit(self: *GameInstance, allocator: Allocator) void {
        // allocator.free(self.state);
        self.state.deinit(allocator);
    }

    pub fn gameUrlForPlayerX(self: *GameInstance) []const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var buf: [13 + 36 + 10 + 36]u8 = undefined;

        std.debug.print("SELF IS 111 \"{any}\"\n", .{self});

        const res = std.fmt.bufPrint(&buf, "/game?gameId={s}&playerId={s}", .{
            // self.gameId,
            // self.playerX.id,
            "5f1b1a6e-1e3d-4aca-95a7-8b72142d855b",
            "59322738-e0f2-4caa-a13b-5e5f6bcd0c3e",
        }) catch |err| {
            std.debug.print("failed to buffprint !!!! ERR: {any}\n", .{err});

            return "failure";
        };

        std.debug.print("RES IS IS 111 \"{any}\"\n", .{res});

        return res;
    }

    /// I still have no idea why this returns garbage
    /// even though inlining it from where it is called works
    /// the size of []const u8 is known at compile time, and this should compile to
    /// "pub fn gameUrlForPlayerX(self: GameInstance) []const u8" above!
    pub fn gameUrlForPlayerXComptime(self: *GameInstance) []const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        std.debug.print("SELF IS 222 \"{any}\"\n", .{self});

        return "/game?gameId=" ++ self.gameId.format_uuid() ++ "&playerId=" ++ self.playerX.id.format_uuid();
    }
    pub fn gameUrlForPlayerO(self: *GameInstance) []const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return "/game?gameId=" ++ self.gameId.format_uuid() ++ "&playerId=" ++ self.playerO.id.format_uuid();
    }
    pub fn gameUrlForPlayer(self: *GameInstance, player: game.PlayerKind) []const u8 {
        return switch (player) {
            .X => self.gameUrlForPlayerX(),
            .Y => self.gameUrlForPlayerO(),
        };
    }
};

pub const GameRepo = struct {
    allocator: Allocator,
    games: std.AutoHashMap(uuid.UUID, GameInstance) = undefined,

    pub fn init(allocator: Allocator) GameRepo {
        return .{
            .allocator = allocator,
            .games = std.AutoHashMap(uuid.UUID, GameInstance).init(allocator),
        };
    }

    pub fn deinit(self: *GameRepo) void {
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

        try self.games.put(game_instance.gameId, game_instance);

        return game_instance;
    }

    pub fn get(self: *GameRepo, game_id: uuid.UUID) ?GameInstance {
        return self.games.get(game_id);
    }

    pub fn delete(self: *GameRepo, game_id: uuid.UUID) bool {
        var val = self.games.get(game_id);

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
    try testing.expectEqual(3, g.state.size);

    const ok = r.delete(g.gameId);

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
