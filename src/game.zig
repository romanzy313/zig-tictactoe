const std = @import("std");
const UUID = @import("uuid").UUID;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const ArrayList = std.ArrayList;
const ArenaAllocator = std.heap.ArenaAllocator;
const Board = @import("Board.zig");
const Ai = @import("Ai.zig");
const Event = @import("events.zig").Event;
const EventEnvelope = @import("events.zig").EventEnvelope;
const GameState = @import("GameState.zig");

const log = std.log.scoped(.game_server);

// Global static struct with typed methods... pretty elegant I think
pub const PublisherUsage = struct {
    // self help untyped internally function
    // will not publish any events if publisher is null
    pub fn publishEvent(publisher: anytype, ev: Event) void {
        const ti = @typeInfo(@TypeOf(publisher));

        switch (ti) {
            .Null => return,
            else => publisher.publishEvent(ev),
        }
    }
};

pub const Status = enum {
    // TODO: add idle
    starting,
    playing,
    stalemate,
    hasWinner,

    pub fn isPlaying(self: Status) bool {
        return self == .playing;
    }
};

pub const PlayerSide = enum(u1) {
    x,
    o,
    pub fn other(self: PlayerSide) PlayerSide {
        if (self == .x) {
            return .o;
        }
        return .x;
    }
};
pub const GameOutcome = enum {
    stalemate,
    xWon,
    oWon,
};
pub const PlayerKind = enum(u1) { human, ai };
pub const AnyPlayerId = union(enum(u1)) {
    human: UUID,
    ai: Ai.Difficulty,
};

pub fn CoreGameGeneric(
    comptime IPublisher: type,
    comptime _publishEventEnvelope: *const fn (T: *IPublisher, envelope: EventEnvelope) void, // instead implement the publishEnvelope... I guess this will need to keep track of
) type {
    return struct {
        ptr_publisher: *IPublisher,

        game_id: UUID, // should be included, as envelopes are sent now
        seq_id: u32 = 0,

        state: GameState,

        const CoreGame = @This();

        pub fn publishEvent(self: *CoreGame, event: Event) void {
            const envelope = EventEnvelope{
                .game_id = self.game_id,
                .seq_id = self.seq_id,
                .timestamp = 100, // current timestamp, its a sideeffect!
                .event = event,
            };
            _publishEventEnvelope(self.ptr_publisher, envelope);
        }

        pub fn init(allocator: Allocator, ptr_publisher: *IPublisher, game_id: UUID, events: []const Event) !CoreGame {
            const state = try GameState.init(allocator, events);

            return CoreGame{
                .ptr_publisher = ptr_publisher,
                .state = state,
                .game_id = game_id,
            };
        }

        pub fn deinit(self: *CoreGame) void {
            self.state.deinit();
        }

        pub fn resolveEventSafe(self: *CoreGame, ev: Event) void {
            const is_server = true;
            // self duck typed to handle "one-time use generics... more like an interface"
            self.state.handleEvent(ev, self, is_server) catch |err| {
                self.publishEvent(.{
                    .__runtimeError = Event.RuntimeError.fromError(err),
                });
            };
        }
    };
}

// tests

const testing = std.testing;

pub fn GameServerGeneric(
    comptime IPublisherEnvelope: type,
    comptime publishEnvelope: *const fn (T: *IPublisherEnvelope, ev: EventEnvelope) void,
) type {
    return struct {
        const CoreGame = CoreGameGeneric(
            IPublisherEnvelope,
            publishEnvelope,
        );

        allocator: Allocator,
        ptr_publisher_envelope: *IPublisherEnvelope,

        instances: ArrayList(CoreGame),
        lookup_map: std.AutoHashMap(UUID, usize),

        const GameServer = @This();

        pub fn init(allocator: Allocator, ptr_publisher_envelope: *IPublisherEnvelope) GameServer {
            return GameServer{
                .allocator = allocator,
                .ptr_publisher_envelope = ptr_publisher_envelope,
                .instances = ArrayList(CoreGame).init(allocator),
                .lookup_map = std.AutoHashMap(UUID, usize).init(allocator),
            };
        }
        pub fn deinit(self: *GameServer) void {
            for (self.instances.items) |*game_instance| {
                game_instance.deinit();
            }
            self.instances.deinit();
            self.lookup_map.deinit();
        }

        pub fn onEnvelope(self: *GameServer, envelope: EventEnvelope) void {
            if (self.getGameInstance(envelope.game_id)) |game_instance| {
                game_instance.resolveEventSafe(envelope.event);
            }
        }

        pub fn newGame(self: *GameServer, game_id: UUID, events: []const Event) !void {
            const game_instance = try CoreGame.init(self.allocator, self.ptr_publisher_envelope, game_id, events);

            try self.instances.append(game_instance);
            const index = self.instances.items.len - 1; // rough

            try self.lookup_map.put(game_id, index);
        }

        fn getGameInstance(self: *GameServer, id: UUID) ?*CoreGame {
            const maybe_index = self.lookup_map.get(id);

            if (maybe_index == null) {
                log.warn("[getGame]: game with uuid {s} not found", .{id});
                return null; // explicit
            }
            const index = maybe_index.?;

            // TODO: bounds checking
            return &self.instances.items[index];
        }
        fn hasGame(self: *GameServer, id: UUID) bool {
            return self.game_map.contains(id);
        }
    };
}

// TODO: again...

// test "muliplexed game server" {
//     var publisher = TestIntegration.init();

//     var server = GameServerGeneric(
//         TestIntegration,
//         TestIntegration.publishEvent,
//     ).init(testing.allocator, &publisher);
//     defer server.deinit();

//     const gameUUID = UUID.initFromNumber(9);

//     try server.newGame(
//         gameUUID,
//         &[_]Event{
//             .{ .gameCreated = .{
//                 .boardSize = 3,
//                 .gameId = gameUUID,
//             } },
//             .{ .playerJoined = test_joinHumanX },
//             .{ .playerJoined = test_joinHumanO },
//         },
//     );

//     try testing.expectEqual(gameUUID, server.getGameInstance(gameUUID).?.game_id);

//     try testing.expectEqual(2, server.getGameInstance(gameUUID).?.seq_id);
//     try testing.expectEqual(.x, server.getGameInstance(gameUUID).?.state.current_player);

//     server.onEnvelope(.{
//         .game_id = gameUUID,
//         .timestamp = 55, //??? not done in any shape or form
//         .seq_id = 55, //???
//         .event = .{ .moveMade = .{ .side = .x, .position = .{ .x = 2, .y = 1 } } },
//     });

//     try testing.expectEqual(3, server.getGameInstance(gameUUID).?.seq_id);
//     try testing.expectEqual(.o, server.getGameInstance(gameUUID).?.state.current_player);

//     // now invalid move, doesnt count
//     server.onEnvelope(.{
//         .game_id = gameUUID,
//         .timestamp = 55, //??? does not matter?
//         .seq_id = 55, //???
//         .event = .{ .moveMade = .{ .side = .o, .position = .{ .x = 2, .y = 1 } } },
//     });

//     try testing.expectEqual(publisher.values.get(0), EventEnvelope{
//         .game_id = gameUUID,
//         .timestamp = 100, // this must be excluded
//         .seq_id = 3, // sequence id didnt change
//         .event = .{ .__runtimeError = .CannotSelectAlreadySelected },
//     });
// }
