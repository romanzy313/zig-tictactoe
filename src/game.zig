const std = @import("std");
const UUID = @import("uuid").UUID;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const ArrayList = std.ArrayList;

const Board = @import("Board.zig");
const Ai = @import("Ai.zig");
const GameEvent = @import("events.zig").GameEvent;

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

pub fn CoreGameServer(
    comptime is_server: bool, // can this be comptiletime known?
    comptime Iface: type,
    comptime publishEvent: *const fn (T: *Iface, ev: GameEvent) void,
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

        // to avoid constant board.?, we force first event to be available on creation
        fn initInternal(alloc: Allocator, ptr: *Iface, gameCreatedEvent: GameEvent.GameCreated) !Self {
            const board = try Board.initEmpty(alloc, gameCreatedEvent.boardSize);
            return .{
                .ptr = ptr,
                .board = board,
            };
        }

        // should events be owned slice (aka []const event.Event?)
        pub fn init(allocator: Allocator, ptr: *Iface, events: []const GameEvent) !Self {
            // const self = init(allocator)

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

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.board.deinit(allocator);
        }

        pub fn resolveEventSafe(self: *Self, ev: GameEvent) void {
            // for example, wrap it up and send through
            // the ui will have to react to these errors
            // and they are not processed by all the clients
            self.resolveEvent(ev) catch |err| {
                publishEvent(self.ptr, .{ .__runtimeError = err });
            };
        }

        fn resolveEvent(self: *Self, ev: GameEvent) !void {
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

        fn handleMoveMadeEvent(self: *Self, ev: GameEvent.MoveMade) !Status {
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

// tests
//

const testing = std.testing;

const TestIntegration = struct {
    values: std.BoundedArray(GameEvent, 10),

    pub fn init() TestIntegration {
        return .{
            .values = std.BoundedArray(GameEvent, 10){},
        };
    }

    pub fn publishEvent(self: *@This(), ev: GameEvent) void {
        self.values.append(ev) catch @panic("event overflow");
    }
};
const test_joinHumanX = GameEvent.PlayerJoined{
    .playerId = .{ .human = UUID.initFromNumber(0) },
    .side = .x,
};
const test_joinHumanO = GameEvent.PlayerJoined{
    .playerId = .{ .human = UUID.initFromNumber(1) },
    .side = .o,
};
const test_joinAiX = GameEvent.PlayerJoined{
    .playerId = .{ .ai = .easy },
    .side = .x,
};
const test_joinAiO = GameEvent.PlayerJoined{
    .playerId = .{ .ai = .easy },
    .side = .o,
};

test "grid init" {
    var eventer = TestIntegration.init();
    var game = try CoreGameServer(true, TestIntegration, TestIntegration.publishEvent).init(
        testing.allocator,
        &eventer,
        &[_]GameEvent{
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
    var game = try CoreGameServer(true, TestIntegration, TestIntegration.publishEvent).init(
        testing.allocator,
        &eventer,
        &[_]GameEvent{
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
    var game = try CoreGameServer(true, TestIntegration, TestIntegration.publishEvent).init(
        testing.allocator,
        &eventer,
        &[_]GameEvent{
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
    try testing.expectEqual(eventer.values.buffer[0], GameEvent{ .__runtimeError = error.CantPlayYet }); // all these need refactoring

    // cant move as only one player joined
    game.resolveEventSafe(.{
        .playerJoined = .{ .playerId = .{ .human = UUID.init() }, .side = .x },
    });
    game.resolveEventSafe(.{
        .moveMade = .{ .side = .x, .position = .{ .x = 0, .y = 0 } },
    });
    try testing.expectEqual(eventer.values.buffer[1], GameEvent{ .__runtimeError = error.CantPlayYet }); // all these need refactoring

    // cant join to already taken side
    game.resolveEventSafe(.{
        .playerJoined = .{ .playerId = .{ .human = UUID.init() }, .side = .x },
    });
    try testing.expectEqual(eventer.values.buffer[2], GameEvent{ .__runtimeError = error.PlayerOfThisSideAleadyJoined }); // all these need refactoring

    // cant play for the other side
    game.resolveEventSafe(.{
        .playerJoined = .{ .playerId = .{ .human = UUID.init() }, .side = .o },
    });
    game.resolveEventSafe(.{
        .moveMade = .{ .side = .o, .position = .{ .x = 0, .y = 0 } },
    });
    try testing.expectEqual(eventer.values.buffer[3], GameEvent{ .__runtimeError = error.WrongSide }); // all these need refactoring

    //  cant play on occupied square
    game.resolveEventSafe(.{
        .moveMade = .{ .side = .x, .position = .{ .x = 0, .y = 0 } },
    });
    game.resolveEventSafe(.{
        .moveMade = .{ .side = .o, .position = .{ .x = 0, .y = 0 } },
    });
    try testing.expectEqual(eventer.values.buffer[4], GameEvent{ .__runtimeError = error.CannotSelectAlreadySelected }); // all these need refactoring

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
    try testing.expectEqual(eventer.values.buffer[5], GameEvent{ .gameFinished = .{ .outcome = .xWon } }); // all these need refactoring
}
