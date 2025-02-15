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

const log = std.log.scoped(.game_server);

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

// NOTE: game_id is not included!
const GameState = struct {
    game_allocator: ArenaAllocator,

    status: Status = .starting,
    players: [2]?AnyPlayerId = [2]?AnyPlayerId{ null, null }, // first player is x, second player is o
    current_player: PlayerSide = .x,

    board: Board,

    pub fn init(allocator: Allocator, board_size: usize) !GameState {
        // i need board size to start the game state
        var arena = ArenaAllocator.init(allocator);

        // arena has a footgun: https://github.com/ziglang/zig/issues/8312#issuecomment-803493118
        const board = try Board.initEmpty(arena.allocator(), board_size);
        return .{
            .game_allocator = arena,
            .board = board,
        };
    }
    pub fn deinit(self: *GameState) void {
        self.game_allocator.deinit();
    }
};

pub fn CoreGameGeneric(
    comptime is_server: bool, // can this be comptiletime known?
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

        // should events be owned slice (aka []const event.Event?)
        pub fn init(allocator: Allocator, ptr_publisher: *IPublisher, game_id: UUID, events: []const Event) !CoreGame {
            if (events.len == 0) {
                return error.BadEventCount;
            }

            if (events[0] != .gameCreated) {
                return error.BadEvent;
            }

            var self = try initInternal(allocator, ptr_publisher, game_id, events[0].gameCreated);

            for (events[1..]) |ev| {
                try self.resolveEvent(ev);
            }
            return self;
        }

        // to avoid constant board.?, we force first event to be available on creation
        fn initInternal(allocator: Allocator, ptr_publisher: *IPublisher, game_id: UUID, gameCreatedEvent: Event.GameCreated) !CoreGame {
            const state = try GameState.init(allocator, gameCreatedEvent.boardSize);
            return CoreGame{
                .ptr_publisher = ptr_publisher,
                .state = state,
                .game_id = game_id,
            };
        }

        pub fn deinit(self: *CoreGame) void {
            self.state.deinit();
        }

        fn can_play(self: *CoreGame) bool {
            return self.state.status == .playing;
        }

        pub fn resolveEventSafe(self: *CoreGame, ev: Event) void {
            // for example, wrap it up and send through
            // the ui will have to react to these errors
            // and they are not processed by all the clients
            self.resolveEvent(ev) catch |err| {
                self.publishEvent(.{ .__runtimeError = err });
            };
        }

        fn resolveEvent(self: *CoreGame, ev: Event) !void {
            switch (ev) {
                .gameCreated => return error.BadEvent,
                .__runtimeError => @panic("cannot pass __runtimeError into resolveEvent()"),
                .playerJoined => |data| {
                    const index = @as(usize, @intFromEnum(data.side));
                    assert(index <= 1);
                    if (self.state.players[index] == null) {
                        self.state.players[index] = data.playerId;
                    } else {
                        return error.PlayerOfThisSideAleadyJoined;
                    }

                    if (self.state.players[0] != null and self.state.players[1] != null) {
                        self.state.status = .playing;
                    }
                },
                .moveMade => |data| {
                    if (!self.can_play()) {
                        return error.CantPlayYet;
                    }
                    const new_status = try self.handleMoveMadeEvent(data);

                    // const new_status = self.handleMoveMadeEvent(data) catch |err| {
                    //     // send error only as server?
                    //     self.publishEvent(.{ .__runtimeError = err }); // dont increment the sequence... its getting interconnected
                    //     return;
                    // };
                    self.state.status = new_status;

                    const is_ai_move = true;

                    if (is_ai_move) {
                        if (is_server) {
                            // publish correct event only as a server. local play uses server mode
                            // publishEvent(.{ .moveMade = . })
                        }
                    }
                },
                .gameFinished => |data| {
                    // blank event for traceability
                    _ = data;
                },
            }

            self.seq_id += 1;
        }

        // for rollback (future plans again...)
        // some events are not supported
        fn reverseEventReverse(self: *CoreGame, ev: Event) !void {
            switch (ev) {
                .gameCreated, .playerJoined, .gameFinished => return error.NonReversibleEvent, // this should just be silent?
                .__runtimeError => @panic("cannot pass __runtimeError into resolveEventReverse()"),
                .moveMade => |move| {
                    _ = move; // reverse it, assuming the state as if this is after this event fired
                    // but then i cant unfire "game logic events"
                    // in this case its not needed, but for realtime multiplayer for sure.
                    // this idea is insired by git and its diffs of the current state to easily checkout
                },
            }
            _ = self;
        }

        fn handleMoveMadeEvent(self: *CoreGame, ev: Event.MoveMade) !Status {
            // cant use references
            if (self.state.status != .playing) {
                return error.GameFinished;
            }
            // check if its the correct player turn
            const player_side = ev.side;
            if (player_side != self.state.current_player) {
                return error.WrongSide;
            }

            const size = self.state.board.size;
            const pos = ev.position;

            if (pos.y >= size or pos.x >= size) {
                return error.InvalidPosition;
            }

            const selected = self.state.board.getValue(pos);
            if (selected != .empty) {
                return error.CannotSelectAlreadySelected;
            }

            self.state.board.setValue(pos, .x);

            const maybe_win = self.state.board.getWinCondition();

            if (maybe_win) |win| {
                self.state.status = .hasWinner;
                self.state.current_player = win.side;
                self.publishEvent(.{ .gameFinished = .{
                    .outcome = if (win.side == .x) .xWon else .oWon,
                } });
            } else if (self.state.board.hasMovesAvailable()) {
                // switch the players
                self.state.current_player = player_side.other();
            } else {
                self.state.status = .stalemate;
                self.publishEvent(.{ .gameFinished = .{
                    .outcome = .stalemate,
                } });
            }

            return self.state.status;
        }
    };
}

// tests

const testing = std.testing;

const TestIntegration = struct {
    values: std.BoundedArray(EventEnvelope, 10),

    pub fn init() TestIntegration {
        return .{
            .values = std.BoundedArray(EventEnvelope, 10){},
        };
    }

    pub fn publishEvent(self: *@This(), ev: EventEnvelope) void {
        self.values.append(ev) catch @panic("event overflow");
    }
};
const test_joinHumanX = Event.PlayerJoined{
    .playerId = .{ .human = UUID.initFromNumber(0) },
    .side = .x,
};
const test_joinHumanO = Event.PlayerJoined{
    .playerId = .{ .human = UUID.initFromNumber(1) },
    .side = .o,
};
const test_joinAiX = Event.PlayerJoined{
    .playerId = .{ .ai = .easy },
    .side = .x,
};
const test_joinAiO = Event.PlayerJoined{
    .playerId = .{ .ai = .easy },
    .side = .o,
};

test "grid init" {
    var eventer = TestIntegration.init();
    var game = try CoreGameGeneric(true, TestIntegration, TestIntegration.publishEvent).init(
        testing.allocator,
        &eventer,
        UUID.initFromNumber(1),
        &[_]Event{
            .{
                .gameCreated = .{
                    .boardSize = 3,
                    .gameId = UUID.init(),
                },
            },
        },
    );
    defer game.deinit();

    const state = game.state;

    try testing.expectEqual(0, game.seq_id);
    try testing.expectEqual(.starting, state.status);
    try testing.expectEqual(.empty, state.board.getValue(.{ .x = 2, .y = 2 }));

    // state.board.debugPrint();
}

test "make move" {
    var eventer = TestIntegration.init();
    var game = try CoreGameGeneric(true, TestIntegration, TestIntegration.publishEvent).init(
        testing.allocator,
        &eventer,
        UUID.initFromNumber(1),
        &[_]Event{
            .{ .gameCreated = .{
                .boardSize = 3,
                .gameId = UUID.init(),
            } },
            .{ .playerJoined = test_joinHumanX },
            .{ .playerJoined = test_joinHumanO },
        },
    );
    defer game.deinit();

    try testing.expectEqual(2, game.seq_id);
    try testing.expectEqual(.playing, game.state.status);
    try testing.expectEqual(.x, game.state.current_player);

    try game.resolveEvent(.{ .moveMade = .{ .side = .x, .position = .{ .x = 2, .y = 1 } } });
    try testing.expectEqual(3, game.seq_id);
    try testing.expectEqual(.playing, game.state.status);
    try testing.expectEqual(.o, game.state.current_player);

    try game.resolveEvent(.{ .moveMade = .{ .side = .o, .position = .{ .x = 0, .y = 0 } } });
    try testing.expectEqual(4, game.seq_id);
    try testing.expectEqual(.playing, game.state.status);
    try testing.expectEqual(.x, game.state.current_player);

    // try testing.expectEqualSlices(u8,
    //     \\o - -
    //     \\- - x
    //     \\- - -
    // , list.items);
}

test "common errors and errors" {
    var eventer = TestIntegration.init();
    var game = try CoreGameGeneric(true, TestIntegration, TestIntegration.publishEvent).init(
        testing.allocator,
        &eventer,
        UUID.initFromNumber(9),
        &[_]Event{
            .{ .gameCreated = .{
                .boardSize = 3,
                .gameId = UUID.initFromNumber(9),
            } },
        },
    );
    defer game.deinit();

    // cant move as no player joined
    game.resolveEventSafe(.{
        .moveMade = .{ .side = .x, .position = .{ .x = 0, .y = 0 } },
    });
    try testing.expectEqual(eventer.values.buffer[0].event, Event{ .__runtimeError = error.CantPlayYet }); // all these need refactoring
    try testing.expectEqual(eventer.values.buffer[0].seq_id, 0); // no events were added

    // cant move as only one player joined
    game.resolveEventSafe(.{
        .playerJoined = .{ .playerId = .{ .human = UUID.init() }, .side = .x },
    });
    game.resolveEventSafe(.{
        .moveMade = .{ .side = .x, .position = .{ .x = 0, .y = 0 } },
    });
    try testing.expectEqual(eventer.values.buffer[1].event, Event{ .__runtimeError = error.CantPlayYet }); // all these need refactoring
    try testing.expectEqual(eventer.values.buffer[1].seq_id, 1); // one event added

    // cant join to already taken side
    game.resolveEventSafe(.{
        .playerJoined = .{ .playerId = .{ .human = UUID.init() }, .side = .x },
    });
    try testing.expectEqual(eventer.values.buffer[2].event, Event{ .__runtimeError = error.PlayerOfThisSideAleadyJoined }); // all these need refactoring

    // cant play for the other side
    game.resolveEventSafe(.{
        .playerJoined = .{ .playerId = .{ .human = UUID.init() }, .side = .o },
    });
    game.resolveEventSafe(.{
        .moveMade = .{ .side = .o, .position = .{ .x = 0, .y = 0 } },
    });
    try testing.expectEqual(eventer.values.buffer[3].event, Event{ .__runtimeError = error.WrongSide }); // all these need refactoring
    try testing.expectEqual(eventer.values.buffer[3].seq_id, 2); // one event added, this is bad testing...

    //  cant play on occupied square
    game.resolveEventSafe(.{
        .moveMade = .{ .side = .x, .position = .{ .x = 0, .y = 0 } },
    });
    game.resolveEventSafe(.{
        .moveMade = .{ .side = .o, .position = .{ .x = 0, .y = 0 } },
    });
    try testing.expectEqual(eventer.values.buffer[4].event, Event{ .__runtimeError = error.CannotSelectAlreadySelected }); // all these need refactoring

    // play till win
    game.resolveEventSafe(.{
        .moveMade = .{ .side = .o, .position = .{ .x = 1, .y = 0 } },
    });
    game.resolveEventSafe(.{
        .moveMade = .{ .side = .x, .position = .{ .x = 0, .y = 1 } },
    });
    game.resolveEventSafe(.{
        .moveMade = .{ .side = .o, .position = .{ .x = 1, .y = 1 } },
    });
    game.resolveEventSafe(.{
        .moveMade = .{ .side = .x, .position = .{ .x = 0, .y = 2 } },
    });
    // expect a gameFinished event
    try testing.expectEqual(eventer.values.buffer[5].event, Event{ .gameFinished = .{ .outcome = .xWon } }); // all these need refactoring
}

pub fn GameServerGeneric(
    comptime is_server: bool, // can this be comptiletime known?
    comptime IPublisherEnvelope: type,
    comptime publishEnvelope: *const fn (T: *IPublisherEnvelope, ev: EventEnvelope) void,
) type {
    return struct {
        const CoreGame = CoreGameGeneric(
            is_server,
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

test "muliplexed game server" {
    var publisher = TestIntegration.init();

    var server = GameServerGeneric(
        true,
        TestIntegration,
        TestIntegration.publishEvent,
    ).init(testing.allocator, &publisher);
    defer server.deinit();

    const gameUUID = UUID.initFromNumber(9);

    try server.newGame(
        gameUUID,
        &[_]Event{
            .{ .gameCreated = .{
                .boardSize = 3,
                .gameId = gameUUID,
            } },
            .{ .playerJoined = test_joinHumanX },
            .{ .playerJoined = test_joinHumanO },
        },
    );

    try testing.expectEqual(gameUUID, server.getGameInstance(gameUUID).?.game_id);

    try testing.expectEqual(2, server.getGameInstance(gameUUID).?.seq_id);
    try testing.expectEqual(.x, server.getGameInstance(gameUUID).?.state.current_player);

    server.onEnvelope(.{
        .game_id = gameUUID,
        .timestamp = 55, //??? not done in any shape or form
        .seq_id = 55, //???
        .event = .{ .moveMade = .{ .side = .x, .position = .{ .x = 2, .y = 1 } } },
    });

    try testing.expectEqual(3, server.getGameInstance(gameUUID).?.seq_id);
    try testing.expectEqual(.o, server.getGameInstance(gameUUID).?.state.current_player);

    // now invalid move, doesnt count
    server.onEnvelope(.{
        .game_id = gameUUID,
        .timestamp = 55, //??? does not matter?
        .seq_id = 55, //???
        .event = .{ .moveMade = .{ .side = .o, .position = .{ .x = 2, .y = 1 } } },
    });

    try testing.expectEqual(publisher.values.get(0), EventEnvelope{
        .game_id = gameUUID,
        .timestamp = 100, // this must be excluded
        .seq_id = 3, // sequence id didnt change
        .event = .{ .__runtimeError = error.CannotSelectAlreadySelected },
    });
}
