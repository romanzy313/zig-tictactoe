const std = @import("std");
const UUID = @import("uuid").UUID;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const testing_allocator = std.testing.allocator;
const testing = std.testing;
const ArrayList = std.ArrayList;

const Board = @import("Board.zig");
const Ai = @import("Ai.zig");
const GameEvent = @import("events.zig").GameEvent;

pub const Status = enum {
    // TODO: add idle
    stalemate,
    turnX,
    turnO,
    winX,
    winO,

    pub fn isPlaying(self: Status) bool {
        return self == .turnX or self == .turnO;
    }
};

pub const PlayerSide = enum(u1) { x, o };
pub const GameMode = enum {
    withAi,
    multiplayer,
};
pub const GameWinner = enum {
    stalemate,
    x,
    o,
};
pub const PlayerKind = enum(u1) { human, ai };
pub const AnyPlayerId = union(enum(u1)) {
    human: UUID,
    ai: Ai.Difficulty,

    // this can be serialized efficiently
    // if first bit is 0 -> its a uuid, otherwise its an ai
};

pub fn CoreGameServer(
    comptime publishEvent: fn (ev: GameEvent) void,
) type {
    return struct {
        seqId: usize = 0, // for ordering of the events
        status: Status = .turnX,
        players: [2]?AnyPlayerId = [2]?AnyPlayerId{ null, null }, // first player is x, second player is o
        can_play: bool = false, // false when game is being set-up and when its over

        board: Board,

        const Self = @This();

        // maybe will be useful
        pub fn getPlayer(self: *Self, side: PlayerSide) AnyPlayerId {
            // this should not be used until the same is initialized
            assert(self.players[0] != null);
            assert(self.players[1] != null);

            return self.players[side].?;
        }

        // to avoid constant board.?, we force first event to be available on creation
        fn initInternal(alloc: Allocator, gameCreatedEvent: GameEvent.GameCreated) !Self {
            const board = try Board.initEmpty(alloc, gameCreatedEvent.boardSize);
            return .{
                .board = board,
            };
        }

        // should events be owned slice (aka []const event.Event?)
        pub fn init(allocator: Allocator, events: []const GameEvent) !Self {
            // const self = init(allocator)

            if (events.len == 0) {
                return error.BadEventCount;
            }

            if (events[0] != .gameCreated) {
                return error.BadEvent;
            }

            var self = try initInternal(allocator, events[0].gameCreated);

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
                publishEvent(.{ .__runtimeError = err });
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
                .__runtimeError => return error.InternalError,
                .playerJoined => |data| {
                    const index = @as(usize, @intFromEnum(data.side));
                    if (self.players[index] == null) {
                        self.players[index] = data.playerId;
                    } else {
                        return error.PlayerOfThisSideAleadyJoined;
                    }

                    if (self.players[0] != null and self.players[1] != null) {
                        self.can_play = true;
                    }
                },
                .moveMade => |data| {
                    if (!self.can_play) {
                        return error.CantPlayYet;
                    }
                    const new_status = try self.handleModeMadeEvent(data);
                    self.status = new_status;
                },
                .gameFinished => |data| {
                    self.can_play = false;

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

        fn handleModeMadeEvent(self: *Self, ev: GameEvent.MoveMade) !Status {
            if (self.status != .turnX and self.status != .turnO) {
                return error.GameFinished;
            }
            // check if its the correct player turn
            const side = ev.side;
            if ((self.status == .turnX and side == .o) or
                (self.status == .turnO and side == .x))
            {
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

            // mutate the grid
            switch (self.status) {
                .turnX => self.board.setValue(pos, .x),
                .turnO => self.board.setValue(pos, .o),
                else => unreachable,
            }

            const maybe_win_condition = self.board.getWinCondition();

            if (maybe_win_condition) |win| {
                switch (win.side) {
                    .x => {
                        publishEvent(.{ .gameFinished = .{
                            .winner = .x,
                        } });
                        return .winX;
                    },
                    .o => {
                        publishEvent(.{ .gameFinished = .{
                            .winner = .o,
                        } });
                        return .winO;
                    },
                }
            }

            // check if there are available moves
            if (self.board.hasMovesAvailable()) {
                switch (self.status) {
                    .turnX => return .turnO,
                    .turnO => return .turnX,
                    else => unreachable,
                }
            }
            publishEvent(.{ .gameFinished = .{
                .winner = .stalemate,
            } });
            return .stalemate;
        }
    };
}

test "grid init" {
    const publishEvent = struct {
        fn publishEvent(ev: GameEvent) void {
            _ = ev;
        }
    }.publishEvent;

    var game = try CoreGameServer(publishEvent).init(testing_allocator, &[_]GameEvent{
        .{
            .gameCreated = .{
                .boardSize = 3,
                .gameId = UUID.init(),
            },
        },
    });
    defer game.deinit(testing_allocator);

    try testing.expectEqual(0, game.seqId);
    try testing.expectEqual(false, game.can_play);
    try testing.expectEqual(.empty, game.board.getValue(.{ .x = 2, .y = 2 }));

    // state.board.debugPrint();
}

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

test "make move" {
    // std.debug.print("player X {s}\n", .{test_joinHumanX.playerId.human});
    // std.debug.print("player O {s}\n", .{test_joinHumanO.playerId.human});
    const publishEvent = struct {
        fn publishEvent(ev: GameEvent) void {
            _ = ev;
        }
    }.publishEvent;

    var game = try CoreGameServer(publishEvent).init(testing_allocator, &[_]GameEvent{
        .{ .gameCreated = .{
            .boardSize = 3,
            .gameId = UUID.init(),
        } },
        .{ .playerJoined = test_joinHumanX },
        .{ .playerJoined = test_joinHumanO },
    });
    defer game.deinit(testing_allocator);

    try testing.expectEqual(2, game.seqId);
    try testing.expectEqual(.turnX, game.status);

    try game.resolveEvent(.{ .moveMade = .{ .side = .x, .position = .{ .x = 2, .y = 1 } } });
    try testing.expectEqual(3, game.seqId);
    try testing.expectEqual(.turnO, game.status);

    try game.resolveEvent(.{ .moveMade = .{ .side = .o, .position = .{ .x = 0, .y = 0 } } });
    try testing.expectEqual(4, game.seqId);
    try testing.expectEqual(.turnX, game.status);

    // try testing.expectEqualSlices(u8,
    //     \\o - -
    //     \\- - x
    //     \\- - -
    // , list.items);
}

// test "make move errors" {
//     var state = try ResolvedState.init(testing_allocator, .{ .multiplayer = .{
//         .boardSize = 3,
//         .playerSide = .x,
//     } });
//     defer state.deinit(testing_allocator);

//     try std.testing.expectError(error.InvalidPosition, state.resolveEvent(.{ .makeMove = .{ .position = .{ .x = 3, .y = 1 } } }));
//     try testing.expectEqual(0, state.seqId);
//     try state.resolveEvent(.{ .makeMove = .{ .position = .{ .x = 1, .y = 1 } } });

//     try std.testing.expectError(error.CannotSelectAlreadySelected, state.resolveEvent(.{ .makeMove = .{ .position = .{ .x = 1, .y = 1 } } }));

//     state.status = .stalemate;

//     try std.testing.expectError(error.GameFinished, state.resolveEvent(.{ .makeMove = .{ .position = .{ .x = 1, .y = 1 } } }));
// }
