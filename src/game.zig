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
pub fn CoreGameGeneric(
    comptime is_server: bool, // can this be comptiletime known?
    comptime IPublisher: type,
    comptime publishEvent: *const fn (T: *IPublisher, ev: Event) void,
) type {
    return struct {
        // need to old the type here, comptile time only
        ptr_publisher: *IPublisher,
        // gameId: UUID,
        seqId: usize = 0, // for ordering of the events

        status: Status = .starting,
        players: [2]?AnyPlayerId = [2]?AnyPlayerId{ null, null }, // first player is x, second player is o
        current_player: PlayerSide = .x,

        board: Board,

        const CoreGame = @This();

        // should events be owned slice (aka []const event.Event?)
        pub fn init(allocator: Allocator, ptr_publisher: *IPublisher, events: []const Event) !CoreGame {
            if (events.len == 0) {
                return error.BadEventCount;
            }

            if (events[0] != .gameCreated) {
                return error.BadEvent;
            }

            var self = try initInternal(allocator, ptr_publisher, events[0].gameCreated);

            for (events[1..]) |ev| {
                try self.resolveEvent(ev);
            }
            return self;
        }

        // to avoid constant board.?, we force first event to be available on creation
        fn initInternal(alloc: Allocator, ptr_publisher: *IPublisher, gameCreatedEvent: Event.GameCreated) !CoreGame {
            const board = try Board.initEmpty(alloc, gameCreatedEvent.boardSize);
            return CoreGame{
                .ptr_publisher = ptr_publisher,
                .board = board,
            };
        }

        pub fn deinit(self: *CoreGame, allocator: Allocator) void {
            self.board.deinit(allocator);
        }

        // maybe will be useful
        pub fn getCurrentPlayerId(self: *CoreGame) AnyPlayerId {
            // this should not be used until the same is initialized
            assert(self.players[0] != null);
            assert(self.players[1] != null);

            return self.players[self.current_player].?;
        }
        fn can_play(self: *CoreGame) bool {
            return self.status == .playing;
        }

        pub fn resolveEventSafe(self: *CoreGame, ev: Event) void {
            // for example, wrap it up and send through
            // the ui will have to react to these errors
            // and they are not processed by all the clients
            self.resolveEvent(ev) catch |err| {
                publishEvent(self.ptr_publisher, .{ .__runtimeError = err });
            };
        }

        fn resolveEvent(self: *CoreGame, ev: Event) !void {
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

        fn handleMoveMadeEvent(self: *CoreGame, ev: Event.MoveMade) !Status {
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
                publishEvent(self.ptr_publisher, .{ .gameFinished = .{
                    .outcome = if (win.side == .x) .xWon else .oWon,
                } });
            } else if (self.board.hasMovesAvailable()) {
                // switch the players
                self.current_player = player_side.other();
            } else {
                self.status = .stalemate;
                publishEvent(self.ptr_publisher, .{ .gameFinished = .{
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
    var game = try CoreGameGeneric(true, TestIntegration, TestIntegration.publishEvent).init(
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
    var game = try CoreGameGeneric(true, TestIntegration, TestIntegration.publishEvent).init(
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
    var game = try CoreGameGeneric(true, TestIntegration, TestIntegration.publishEvent).init(
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

// envelope stuff, wrapping one time, cant get it working...

const TestPublisherEnvelope = struct {
    values: std.BoundedArray(EventEnvelope, 100),

    pub fn init() TestPublisherEnvelope {
        return .{
            .values = std.BoundedArray(EventEnvelope, 100).init(0) catch unreachable,
        };
    }

    pub fn publishEnvelope(self: *TestPublisherEnvelope, ev: EventEnvelope) void {
        log.err("trying to publish event {any}", .{ev});
        // log.err("self: {any}", .{self});
        log.err("self len: {any}", .{self.values.len}); // len is segmentation fault...
        self.values.append(ev) catch @panic("event overflow");
    }
};

// holds many games in the map
// and it converts the events into their envelopes?
pub fn GameServerGeneric(
    comptime is_server: bool, // can this be comptiletime known?
    comptime IPublisherEnvelope: type,
    comptime publishEnvelope: *const fn (T: *IPublisherEnvelope, ev: EventEnvelope) void,
    // serializeEvent anyone? Using an envelope, probably on the same IFace?
) type {

    // I need a comptime function for IPublisher with Event as a thing...

    return struct {
        // the publish event needs to know what is the game id for proper routing
        // otherwise we just call the same function on all
        // so i need to wrap that, and return publishEvent function with a different pointer for each game?
        const CoreGame = CoreGameGeneric(
            is_server,
            InternalGameInstance,
            InternalGameInstance.publishEvent,
        );
        const InternalGameInstance = struct {
            ptr_publisher_envelope: *IPublisherEnvelope,
            game_id: UUID,
            game: CoreGame,
            // ptr_server: *GameServer,
            // game_idx: usize, // so that I can look it up before sening it?
            pub fn publishEvent(self: *InternalGameInstance, ev: Event) void {
                // const timestamp: u64 = @intCast(std.time.milliTimestamp());
                const timestamp: u64 = 100;

                const envelope = EventEnvelope{
                    .gameId = self.game_id,
                    .seqId = 0,
                    .timestamp = timestamp,
                    .event = ev,
                };
                // double pointer lookup fails when the game tries to publish
                publishEnvelope(self.ptr_publisher_envelope, envelope); // double pointer lookup!
            }
        };

        allocator: Allocator,
        ptr_publisher_envelope: *IPublisherEnvelope,

        instances: ArrayList(InternalGameInstance), // all core games are stored on here, with extra "busy flag". maximum amount of games can be set here
        // the game_map references an instance
        lookup_map: std.AutoHashMap(UUID, usize), //this links uuid to instance id

        const GameServer = @This();

        // here we implement all these things, and keep game interface
        pub fn init(allocator: Allocator, ptr_publisher_envelope: *IPublisherEnvelope) GameServer {
            return GameServer{
                .allocator = allocator,
                .ptr_publisher_envelope = ptr_publisher_envelope,
                .instances = ArrayList(InternalGameInstance).initCapacity(allocator, 30) catch @panic("OOM"),
                .lookup_map = std.AutoHashMap(UUID, usize).init(allocator),
            };
        }
        pub fn deinit(self: *GameServer) void {
            // shutdown, clean everything up
            for (self.instances.items) |*game_instance| {
                // i keep on loosing these pointers...
                game_instance.game.deinit(self.allocator);
            }
            self.instances.deinit();
            self.lookup_map.deinit();
        }

        pub fn onEnvelope(self: *GameServer, envelope: EventEnvelope) void {
            if (self.getGameInstance(envelope.gameId)) |game_instance| {
                log.warn("got game {any}", .{game_instance}); // pointer of publisher is lost...

                game_instance.game.resolveEventSafe(envelope.event);
            }
        }

        pub fn newGame(self: *GameServer, id: UUID, events: []const Event) !void {
            // its wierd that envelope wrapper is not "saved anywhere"
            // its kind of like a closure with static data
            //
            // this must be staying in the map! I think this leaks?
            // var envelope = GameInstance{
            //     // .ptr_publisher = self.ptr_publisher,
            //     .ptr_server = self,
            //     .gameId = id,
            //     .seqId = 0,
            //     .game = undefined, // it depends on self
            // };
            // // the game must be const!
            // const game = CoreGame.init(self.allocator, &envelope, events) catch |err| {
            //     // how to communicate this?
            //     log.warn("failed to init new game: {any}\n", .{err});
            //     // i must return an error?
            //     return error.FailedToInitNewGame;
            // };
            // envelope.game = game; // maybe this moneying fucks this up, as pointers are locally scoped or smth?

            // var internal_game_instance = InternalGameInstance{
            //     .game_id = id,
            //     .ptr_publisher_envelope = self.ptr_publisher_envelope,
            //     .game = undefined,
            // };
            // // &internal_game_instance address not avaiable...
            // var core_game = try CoreGame.init(self.allocator, &internal_game_instance, events);
            // internal_game_instance.game = &core_game;

            var internal_game_instance = InternalGameInstance{
                .game_id = id,
                .ptr_publisher_envelope = self.ptr_publisher_envelope,
                .game = try CoreGame.init(self.allocator, undefined, events),
            };
            // &internal_game_instance address not avaiable...
            internal_game_instance.game.ptr_publisher = &internal_game_instance;

            log.warn("the internal instance is {any}", .{internal_game_instance});

            try self.instances.append(internal_game_instance);
            const index = self.instances.items.len - 1; // rough

            log.warn("the internal instance from slice is {any}", .{self.instances.items[0]});

            try self.lookup_map.put(id, index);
        }
        // https://ziggit.dev/t/problem-with-hashmaps/7221
        // var newList = std.ArrayList(Point).init(allocator);
        // newList is a variable defined on the stack. It will be invalidated at the end of the scope.
        // try map.put(key, &newList);
        // Here you are taking a pointer to it and store it in the map.
        // One line later the scope ends and the pointer points to invalid memory.

        // The solution would be to just don’t store a pointer in the map.
        // Instead you can use map.getPtr to get a pointer to the list stored in the HashMap’s internal memory (you just need to be careful, because such a reference will become invalid after changing the hashmap).
        fn getGameInstance(self: *GameServer, id: UUID) ?InternalGameInstance {
            const maybe_index = self.lookup_map.get(id);

            if (maybe_index == null) {
                log.warn("[getGame]: game with uuid {s} not found", .{id});
                return null; // explicit
            }
            const index = maybe_index.?;

            // TODO: bounds checking
            return self.instances.items[index];
        }
        fn hasGame(self: *GameServer, id: UUID) bool {
            return self.game_map.contains(id);
        }
    };
}

test "muliplexed game server" {
    var publisher = TestPublisherEnvelope.init();
    var server = GameServerGeneric(
        true,
        TestPublisherEnvelope,
        TestPublisherEnvelope.publishEnvelope,
    ).init(testing.allocator, &publisher);
    defer server.deinit();

    const gameUUID = UUID.initFromNumber(10);

    log.warn("game uuid {s}", .{gameUUID});

    _ = try server.newGame(
        gameUUID,
        &[_]Event{
            .{ .gameCreated = .{
                .boardSize = 3,
                .gameId = gameUUID,
            } },
            .{ .playerJoined = test_joinHumanX }, // these must be emitted though a wrapper though
            .{ .playerJoined = test_joinHumanO },
        },
    );
    // I do have deep access here... but why not inside meit
    // these are both good. I cant hold on to pointers for long. As addition of new games will invalidate them
    // because the hashmap will need to grow and all values will be rehashed, therefore previous pointers wont work
    log.warn("CURRENT PLAYER!!!: {any}", .{server.getGameInstance(gameUUID).?.game.current_player});
    log.warn("CURRENT STATUS!!!: {any}", .{server.getGameInstance(gameUUID).?.game.status});

    // outside the game_id is different...
    // they are like infinetely nested, as pointer to self is badly resolved... so what now?
    // accessing "game" yileds trash
    log.warn("OUTSIDE the internal instance from slice is {any}", .{server.instances.items[0].game});

    // server.onEnvelope(.{
    //     .gameId = gameUUID,
    //     .timestamp = 55, //???
    //     .seqId = 55, //???
    //     .event = .{ .moveMade = .{ .side = .x, .position = .{ .x = 2, .y = 1 } } },
    // });

    // try testing.expectEqual(server.getGameInstance(gameUUID).?.seqId, 3); // sequence must be moved into "metadata", and timestamp as well... I think timestamp is pretty important too
    // try testing.expectEqual(server.getGameInstance(gameUUID).?.current_player, .o);

    // log.warn("game_map {any}", .{server.game_map});

    // errornious event is sent
    // server.onEnvelope(.{
    //     .gameId = gameUUID,
    //     .timestamp = 0, //???
    //     .seqId = 0, //???
    //     .event = .{ .moveMade = .{ .side = .x, .position = .{ .x = 2, .y = 1 } } }, // bad event, Segmentation fault at address 0x500000019...
    //     // .event = .{ .moveMade = .{ .side = .o, .position = .{ .x = 1, .y = 1 } } }, // good event
    // });

    // try testing.expectEqual(publisher.values.buffer[0], EventEnvelope{
    //     .gameId = gameUUID,
    //     .seqId = 0,
    //     .timestamp = 0,
    //     .event = .{
    //         .__runtimeError = error.AALLALA,
    //     },
    // }); // all these need refactoring

}
