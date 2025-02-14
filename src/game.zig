const std = @import("std");
const UUID = @import("uuid").UUID;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const ArrayList = std.ArrayList;

const Board = @import("Board.zig");
const Ai = @import("Ai.zig");
const Event = @import("events.zig").Event;
const EventEnvelope = @import("events.zig").EventEnvelope;

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

    // this can be serialized efficiently
    // if first bit is 0 -> its a uuid, otherwise its an ai
};

// FIXME: the game projection must store its own allocator
// there is basically an allocator per-game. and not the shared one, or shared one for now.
pub fn CoreGameProjection(
    comptime is_server: bool, // can this be comptiletime known?
    comptime Iface: type,
    comptime publishEvent: *const fn (T: *Iface, ev: Event) void,
) type {
    return struct {
        // need to old the type here, comptile time only
        ptr: *Iface,
        seqId: usize = 0, // for ordering of the events
        status: Status = .starting,
        players: [2]?AnyPlayerId = [2]?AnyPlayerId{ null, null }, // first player is x, second player is o
        current_player: PlayerSide = .x,

        board: Board,

        const Self = @This();

        // should events be owned slice (aka []const event.Event?)
        pub fn init(allocator: Allocator, ptr: *Iface, events: []const Event) !Self {
            if (events.len == 0) {
                return error.BadEventCount;
            }

            if (events[0] != .gameCreated) {
                return error.BadEvent;
            }

            var self = try initInternal(allocator, ptr, events[0].gameCreated);

            for (events[1..]) |ev| {
                try self.resolveEvent(ev);
            }
            return self;
        }

        // to avoid constant board.?, we force first event to be available on creation
        fn initInternal(alloc: Allocator, ptr: *Iface, gameCreatedEvent: Event.GameCreated) !Self {
            const board = try Board.initEmpty(alloc, gameCreatedEvent.boardSize);
            return .{
                .ptr = ptr,
                .board = board,
            };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.board.deinit(allocator);
        }

        // maybe will be useful
        pub fn getCurrentPlayerId(self: *Self) AnyPlayerId {
            // this should not be used until the same is initialized
            assert(self.players[0] != null);
            assert(self.players[1] != null);

            return self.players[self.current_player].?;
        }
        fn can_play(self: *Self) bool {
            return self.status == .playing;
        }

        pub fn resolveEventSafe(self: *Self, ev: Event) void {
            // for example, wrap it up and send through
            // the ui will have to react to these errors
            // and they are not processed by all the clients
            self.resolveEvent(ev) catch |err| {
                publishEvent(self.ptr, .{ .__runtimeError = err });
            };
        }

        fn resolveEvent(self: *Self, ev: Event) !void {
            // hmm, sequence here must be provided, so that we can validate, basically include some data from the envelope
            // things such as timestamps, but thouse are part of the game, so they should included with the moves. so only meta is sequenceId
            // but cant sequenceIds be resolved upstream?

            // how are errors handled?
            // errors should also be communicated via sendEvent?
            // cause the server cannot crash when resolve event returns an error
            // maybe create a safe wrapper?
            switch (ev) {
                .gameCreated => return error.BadEvent,
                .__runtimeError => @panic("cannot pass __runtimeError into resolveEvent()"),
                .playerJoined => |data| {
                    const index = @as(usize, @intFromEnum(data.side));
                    assert(index <= 1);
                    if (self.players[index] == null) {
                        self.players[index] = data.playerId;
                    } else {
                        return error.PlayerOfThisSideAleadyJoined;
                    }

                    if (self.players[0] != null and self.players[1] != null) {
                        self.status = .playing;
                    }
                },
                .moveMade => |data| {
                    if (!self.can_play()) {
                        return error.CantPlayYet;
                    }
                    const new_status = try self.handleMoveMadeEvent(data);
                    self.status = new_status;

                    const is_ai_move = true;

                    if (is_ai_move) {
                        if (is_server) {
                            // publish correct event only as a server. local play uses server mode
                            // publishEvent(.{ .moveMade = . })
                        }
                    }

                    // here generate ai.Move event
                    // but on client I may not need to do this
                    // cause here I am not trusting the client, the resulting value is non-deterministic
                    // so i need to know if im a server host!
                },
                .gameFinished => |data| {
                    _ = data;
                    // no need to actually do this, the client does it automatically
                    // self.status = switch (data.winner) {
                    //     .x => .winX,
                    //     .o => .winO,
                    //     .stalemate => .stalemate,
                    // };
                },
                // additionally error events could be sent?

                // .makeMove => |moveEv| {
                //     const newStatus = try self.handleMakeMoveEvent(moveEv.position);
                //     self.status = newStatus;
                // },
            }

            self.seqId += 1;
        }

        fn handleMoveMadeEvent(self: *Self, ev: Event.MoveMade) !Status {
            if (self.status != .playing) {
                return error.GameFinished;
            }
            // check if its the correct player turn
            const player_side = ev.side;
            if (player_side != self.current_player) {
                return error.WrongSide;
            }

            const size = self.board.size;
            const pos = ev.position;

            if (pos.y >= size or pos.x >= size) {
                return error.InvalidPosition;
            }

            const selected = self.board.getValue(pos);
            if (selected != .empty) {
                return error.CannotSelectAlreadySelected;
            }

            self.board.setValue(pos, .x);

            const maybe_win = self.board.getWinCondition();

            if (maybe_win) |win| {
                self.status = .hasWinner;
                self.current_player = win.side;
                publishEvent(self.ptr, .{ .gameFinished = .{
                    .outcome = if (win.side == .x) .xWon else .oWon,
                } });
            } else if (self.board.hasMovesAvailable()) {
                // switch the players
                self.current_player = player_side.other();
            } else {
                self.status = .stalemate;
                publishEvent(self.ptr, .{ .gameFinished = .{
                    .outcome = .stalemate,
                } });
            }

            return self.status;
        }
    };
}

const log = std.log.scoped(.game_server);

// i publisher needs to be implemented to redirect events on self (in local play)
//

// holds many games in the map
// and it converts the events into their envelopes?
pub fn GameServer(
    comptime is_server: bool, // can this be comptiletime known?
    comptime IPublisher: type,
    comptime publishEnvelope: *const fn (T: *IPublisher, ev: EventEnvelope) void,
    // serializeEvent anyone? Using an envelope, probably on the same IFace?
) type {
    return struct {
        // the publish event needs to know what is the game id for proper routing
        // otherwise we just call the same function on all
        // so i need to wrap that, and return publishEvent function with a different pointer for each game?
        const GameProjection = CoreGameProjection(
            is_server,
            EnvelopeWrapper,
            EnvelopeWrapper.publishEvent,
        );

        allocator: Allocator,
        ptr_publisher: *IPublisher,
        game_map: std.AutoHashMap(UUID, GameProjection),

        const Self = @This();

        // here we implement all these things, and keep game interface
        pub fn init(allocator: Allocator, ptr_publisher: *IPublisher) Self {
            return .{
                .allocator = allocator,
                .ptr_publisher = ptr_publisher,
                .game_map = std.AutoHashMap(UUID, GameProjection).init(allocator),
            };
        }
        pub fn deinit(self: *Self) void {
            // shutdown, clean everything up
            var it = self.game_map.valueIterator();
            while (it.next()) |game| {
                game.deinit(self.allocator); // maybe every game should store its own allocator? that seems reasonable!
            }
            self.game_map.deinit();
        }
        // envelope wrapper here!
        const EnvelopeWrapper = struct {
            ptr_server: *Self,
            gameId: UUID,
            seqId: u32 = 0, // this is not doing well, as game starts with event 0. maybe it starts with event 1, in order to signify nullity of the situation

            // function to expose the
            pub fn publishEvent(self: *EnvelopeWrapper, ev: Event) void {

                // can do hasGame...
                if (self.ptr_server.getGame(self.gameId)) |game| {
                    _ = game; // not used for now, but some data could be useful

                    const timestamp: u64 = @intCast(std.time.milliTimestamp());

                    const envelope = EventEnvelope{
                        .gameId = self.gameId,
                        .seqId = self.seqId,
                        .timestamp = timestamp,
                        .event = ev,
                    };
                    self.seqId += 1;
                    publishEnvelope(self.ptr_server.ptr_publisher, envelope); // double pointer lookup!
                }
            }
        };

        pub fn onEnvelope(self: *Self, envelope: EventEnvelope) void {
            if (self.getGame(envelope.gameId)) |game| {
                game.resolveEventSafe(envelope.event);
            }
        }

        pub fn newGame(self: *Self, id: UUID, events: []const Event) !*GameProjection {
            // its wierd that envelope wrapper is not "saved anywhere"
            // its kind of like a closure with static data
            var envelope = EnvelopeWrapper{
                .gameId = id,
                .ptr_server = self,
                .seqId = 0,
            };

            // allocator is passed in!
            var game = GameProjection.init(self.allocator, &envelope, events) catch |err| {
                // how to communicate this?
                log.warn("failed to init new game: {any}\n", .{err});
                // i must return an error?
                return error.FailedToInitNewGame;
            };

            try self.game_map.put(id, game);
            return &game;
        }

        fn getGame(self: *Self, id: UUID) ?*GameProjection {
            const maybe_game = self.game_map.getPtr(id);

            if (maybe_game == null) {
                log.warn("[getGame]: game with uuid {s} not found", .{id});
                return null; // explicit
            }

            return maybe_game.?;
        }
        fn hasGame(self: *Self, id: UUID) bool {
            return self.game_map.contains(id);
        }
    };
}

// tests

const testing = std.testing;

const TestIntegration = struct {
    values: std.BoundedArray(Event, 10),

    pub fn init() TestIntegration {
        return .{
            .values = std.BoundedArray(Event, 10){},
        };
    }

    pub fn publishEvent(self: *@This(), ev: Event) void {
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
    var game = try CoreGameProjection(true, TestIntegration, TestIntegration.publishEvent).init(
        testing.allocator,
        &eventer,
        &[_]Event{
            .{
                .gameCreated = .{
                    .boardSize = 3,
                    .gameId = UUID.init(),
                },
            },
        },
    );
    defer game.deinit(testing.allocator);

    try testing.expectEqual(0, game.seqId);
    try testing.expectEqual(.starting, game.status);
    try testing.expectEqual(.empty, game.board.getValue(.{ .x = 2, .y = 2 }));

    // state.board.debugPrint();
}

test "make move" {
    var eventer = TestIntegration.init();
    var game = try CoreGameProjection(true, TestIntegration, TestIntegration.publishEvent).init(
        testing.allocator,
        &eventer,
        &[_]Event{
            .{ .gameCreated = .{
                .boardSize = 3,
                .gameId = UUID.init(),
            } },
            .{ .playerJoined = test_joinHumanX },
            .{ .playerJoined = test_joinHumanO },
        },
    );
    defer game.deinit(testing.allocator);

    try testing.expectEqual(2, game.seqId);
    try testing.expectEqual(.playing, game.status);
    try testing.expectEqual(.x, game.current_player);

    try game.resolveEvent(.{ .moveMade = .{ .side = .x, .position = .{ .x = 2, .y = 1 } } });
    try testing.expectEqual(3, game.seqId);
    try testing.expectEqual(.playing, game.status);
    try testing.expectEqual(.o, game.current_player);

    try game.resolveEvent(.{ .moveMade = .{ .side = .o, .position = .{ .x = 0, .y = 0 } } });
    try testing.expectEqual(4, game.seqId);
    try testing.expectEqual(.playing, game.status);
    try testing.expectEqual(.x, game.current_player);

    // try testing.expectEqualSlices(u8,
    //     \\o - -
    //     \\- - x
    //     \\- - -
    // , list.items);
}

test "common errors and errors" {
    var eventer = TestIntegration.init();
    var game = try CoreGameProjection(true, TestIntegration, TestIntegration.publishEvent).init(
        testing.allocator,
        &eventer,
        &[_]Event{
            .{ .gameCreated = .{
                .boardSize = 3,
                .gameId = UUID.initFromNumber(0),
            } },
        },
    );
    defer game.deinit(testing.allocator);

    // cant move as no player joined
    game.resolveEventSafe(.{
        .moveMade = .{ .side = .x, .position = .{ .x = 0, .y = 0 } },
    });
    try testing.expectEqual(eventer.values.buffer[0], Event{ .__runtimeError = error.CantPlayYet }); // all these need refactoring

    // cant move as only one player joined
    game.resolveEventSafe(.{
        .playerJoined = .{ .playerId = .{ .human = UUID.init() }, .side = .x },
    });
    game.resolveEventSafe(.{
        .moveMade = .{ .side = .x, .position = .{ .x = 0, .y = 0 } },
    });
    try testing.expectEqual(eventer.values.buffer[1], Event{ .__runtimeError = error.CantPlayYet }); // all these need refactoring

    // cant join to already taken side
    game.resolveEventSafe(.{
        .playerJoined = .{ .playerId = .{ .human = UUID.init() }, .side = .x },
    });
    try testing.expectEqual(eventer.values.buffer[2], Event{ .__runtimeError = error.PlayerOfThisSideAleadyJoined }); // all these need refactoring

    // cant play for the other side
    game.resolveEventSafe(.{
        .playerJoined = .{ .playerId = .{ .human = UUID.init() }, .side = .o },
    });
    game.resolveEventSafe(.{
        .moveMade = .{ .side = .o, .position = .{ .x = 0, .y = 0 } },
    });
    try testing.expectEqual(eventer.values.buffer[3], Event{ .__runtimeError = error.WrongSide }); // all these need refactoring

    //  cant play on occupied square
    game.resolveEventSafe(.{
        .moveMade = .{ .side = .x, .position = .{ .x = 0, .y = 0 } },
    });
    game.resolveEventSafe(.{
        .moveMade = .{ .side = .o, .position = .{ .x = 0, .y = 0 } },
    });
    try testing.expectEqual(eventer.values.buffer[4], Event{ .__runtimeError = error.CannotSelectAlreadySelected }); // all these need refactoring

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
    try testing.expectEqual(eventer.values.buffer[5], Event{ .gameFinished = .{ .outcome = .xWon } }); // all these need refactoring
}

const TestPublisherEnvelope = struct {
    values: std.BoundedArray(EventEnvelope, 10),

    pub fn init() TestPublisherEnvelope {
        return .{
            .values = std.BoundedArray(EventEnvelope, 10){},
        };
    }

    pub fn publishEnvelope(self: *@This(), ev: EventEnvelope) void {
        self.values.append(ev) catch @panic("event overflow");
    }
};

test "muliplexed game server" {
    var publisher = TestPublisherEnvelope.init();
    var server = GameServer(
        true,
        TestPublisherEnvelope,
        TestPublisherEnvelope.publishEnvelope,
    ).init(testing.allocator, &publisher);
    defer server.deinit();

    const gameUUID = UUID.initFromNumber(10);

    _ = try server.newGame(
        gameUUID,
        &[_]Event{
            .{ .gameCreated = .{
                .boardSize = 3,
                .gameId = UUID.initFromNumber(0),
            } },
            .{ .playerJoined = test_joinHumanX }, // these must be emitted though a wrapper though
            .{ .playerJoined = test_joinHumanO },
        },
    );

    server.onEnvelope(.{
        .gameId = gameUUID,
        .timestamp = 0, //???
        .seqId = 0, //???
        .event = .{ .moveMade = .{ .side = .x, .position = .{ .x = 2, .y = 1 } } },
    });

    try testing.expectEqual(server.getGame(gameUUID).?.seqId, 3); // sequence must be moved into "metadata"
    try testing.expectEqual(server.getGame(gameUUID).?.current_player, .o);
}
