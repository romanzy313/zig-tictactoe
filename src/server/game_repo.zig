// const std = @import("std");
// const testing = std.testing;
// const Allocator = std.mem.Allocator;
// const common = @import("common");
// const game = common.game;
// const ResolvedState = common.game.ResolvedState;

// const Mutex = std.Thread.Mutex;

// // FIXME: this should always be referenced by a pointer
// // because the amount of data stored is huge!
// // idk what goes on behind the hood now...
// pub const GameInstance = struct {
//     gameId: uuid.UUID, // this is a fixed size though...
//     playerX: game.AnyPlayer,
//     playerO: game.AnyPlayer,
//     state: ResolvedState,

//     // dont forget to deinit state!
//     // any player could be an AI though...
//     // and AI MUST be ran on the outside machine for "proper learning experience"
//     // AI MUST be a stateful object which can be accessed by network
//     pub fn initRandom(allocator: Allocator) !GameInstance {
//         const state = try ResolvedState.init(allocator, 3);
//         return .{
//             .gameId = uuid.newV4(),
//             .playerX = game.AnyPlayer.random(.human), // this needs to be determined
//             .playerO = game.AnyPlayer.random(.ai), // ai id is created here, but ai must be made separately...
//             .state = state,
//         };
//     }

//     pub fn deinit(self: *GameInstance, allocator: Allocator) void {
//         // allocator.free(self.state);
//         self.state.deinit(allocator);
//     }

//     pub fn gameUrlForPlayerX(self: *GameInstance, allocator: Allocator) ![]const u8 {
//         return try std.fmt.allocPrint(allocator, "/game?gameId={s}&playerId={s}", .{ self.gameId, self.playerX.id });
//     }
//     pub fn gameUrlForPlayerO(self: *GameInstance, allocator: Allocator) ![]const u8 {
//         return try std.fmt.allocPrint(allocator, "/game?gameId={s}&playerId={s}", .{ self.gameId, self.playerO.id });
//     }
//     pub fn gameUrlForPlayer(self: *GameInstance, player: game.PlayerKind) ![]const u8 {
//         return try switch (player) {
//             .X => self.gameUrlForPlayerX(),
//             .Y => self.gameUrlForPlayerO(),
//         };
//     }
// };

// pub const GameRepo = struct {
//     allocator: Allocator,
//     games: std.AutoHashMap(uuid.UUID, GameInstance),

//     pub fn init(allocator: Allocator) GameRepo {
//         return .{
//             .allocator = allocator,
//             .games = std.AutoHashMap(uuid.UUID, GameInstance).init(allocator),
//         };
//     }

//     pub fn deinit(self: *GameRepo) void {
//         var iter = self.games.valueIterator();
//         while (iter.next()) |entry| {
//             entry.deinit(self.allocator);
//         }
//         self.games.deinit();
//     }

//     /// creates a new game and returns it
//     /// memory is freed automatically on delete()
//     pub fn newGame(self: *GameRepo) !GameInstance {
//         const game_instance = try GameInstance.initRandom(self.allocator);

//         try self.games.put(game_instance.gameId, game_instance);

//         return game_instance;
//     }

//     pub fn get(self: *GameRepo, game_id: uuid.UUID) ?GameInstance {
//         return self.games.get(game_id);
//     }

//     // example from here, which dupes everything, which I am not doing...
//     // https://github.com/cztomsik/tokamak/blob/main/examples/blog/src/model.zig
//     pub fn getAllOwned(self: *GameRepo) ![]const GameInstance {
//         var res = std.ArrayList(GameInstance).init(self.allocator);
//         errdefer res.deinit(); // because toOwnSlice releases "memory lock"

//         var iter = self.games.iterator();

//         while (iter.next()) |v| {
//             try res.append(v.value_ptr.*);
//         }

//         return res.toOwnedSlice();
//     }

//     pub fn delete(self: *GameRepo, game_id: uuid.UUID) bool {
//         var val = self.games.get(game_id);

//         // std.debug.print("???? game_id={s}, val={any} \n", .{ game_id, val });

//         if (val == null) {
//             return false;
//         }

//         // dont forget to free the state!
//         // this is awkward...
//         defer val.?.deinit(self.allocator);

//         const ok = self.games.remove(game_id);

//         // if (ok) {
//         //     val.?.deinit(self.allocator);
//         // }

//         return ok;
//     }
// };

// test "adding and removing games" {
//     const testing_allocator = testing.allocator;

//     var r = GameRepo.init(testing_allocator);
//     defer r.deinit();

//     const g = try r.newGame();

//     try testing.expectEqual(1, r.games.count());
//     try testing.expectEqual(3, g.state.size);

//     const ok = r.delete(g.gameId);

//     try testing.expect(ok);
// }

// test "autocleanup on deinit" {
//     const testing_allocator = testing.allocator;

//     var r = GameRepo.init(testing_allocator);

//     _ = try r.newGame();

//     // std.debug.print("GOT GAME {s}\n", .{g.game_id});

//     try testing.expectEqual(1, r.games.count());

//     // expect no leaks
//     r.deinit();
// }
