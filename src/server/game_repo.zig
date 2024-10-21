const std = @import("std");
const Allocator = std.mem.Allocator;
const common = @import("common");
const State = common.game.State;
const uuid = @import("vendor").uuid;

pub const PlayerId = []const u8;

// trying to follow this https://nathancraddock.com/blog/zig-naming-conventions/

pub const GameState = struct {
    game_id: []const u8, // this is a fixed size though...
    player_x: PlayerId, // and these are too
    player_o: PlayerId,
    state: *State,
    // i need to embed the game.State here...
    // so it must be common, I must register it under a common "module", via build.zig
};

pub const GameRepo = struct {
    allocator: Allocator,
    games: std.StringHashMap(GameState),

    pub fn init(allocator: Allocator) GameRepo {
        const games = std.StringHashMap(GameState).init(allocator);
        return .{
            .allocator = allocator,
            .games = games,
        };
    }

    pub fn deinit(self: GameRepo) void {
        // remove all games

        self.games
            .self.games.deinit();
    }

    pub fn new(self: *GameRepo) !GameState {
        const game_id = uuid.newV4().format_uuid();
        const game_state: GameState = .{
            .game_id = game_id,
            .player_x = uuid.newV4().format_uuid(),
            .player_o = uuid.newV4().format_uuid(),
            .state = State.init(self.allocator, 3),
        };

        try self.games.put(game_id, game_state);

        return game_state;
    }

    pub fn get(self: *GameRepo, game_id: []const u8) !GameState {
        return try self.games.get(game_id);
    }

    pub fn delete(self: *GameRepo, game_id: []const u8) bool {
        return self.games.remove(game_id);
    }
};
