const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const assert = std.debug.assert;

const UUID = @import("uuid").UUID;
const Ai = @import("Ai.zig");
const Board = @import("Board.zig");
const Event = @import("events.zig").Event;
const PublisherUsage = @import("game.zig").PublisherUsage;
const Status = @import("game.zig").Status;
const AnyPlayerId = @import("game.zig").AnyPlayerId;
const PlayerSide = @import("game.zig").PlayerSide;

const GameState = @This();

game_allocator: ArenaAllocator,

status: Status = .starting,
players: [2]?AnyPlayerId = [2]?AnyPlayerId{ null, null }, // first player is x, second player is o
current_player: PlayerSide = .x,

board: Board,

// inits from existing events
// note that no events can be emitted, as this must include full history
pub fn init(allocator: Allocator, events: []const Event) !GameState {
    if (events.len == 0 or events[0] != .gameCreated) {
        return error.BadInitialEvent;
    }

    // i need board size to start the game state
    var arena = ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    // arena has a footgun: https://github.com/ziglang/zig/issues/8312#issuecomment-803493118
    const board = try Board.initEmpty(arena.allocator(), events[0].gameCreated.boardSize);
    var self = GameState{
        .game_allocator = arena,
        .board = board,
    };

    for (events[1..]) |ev| {
        try self.handleEvent(ev, null, true); // this is a special case, where we cant emit events? everything is replayed
    }

    return self;
}
pub fn deinit(self: *GameState) void {
    self.game_allocator.deinit();
}

fn can_play(self: *GameState) bool {
    return self.status == .playing;
}

pub fn writeStatus(self: *GameState, writer: anytype) !void {
    switch (self.status) {
        .starting => try writer.print("Waiting for game to start", .{}),
        .playing => switch (self.current_player) {
            .x => try writer.print("Player X turn", .{}),
            .o => try writer.print("Player O turn", .{}),
        },
        .hasWinner => switch (self.current_player) {
            .x => try writer.print("Player X won", .{}),
            .o => try writer.print("Player O won", .{}),
        },
        .stalemate => try writer.print("Stalemate", .{}),
    }
}
pub fn getStatus(self: *GameState) []const u8 {
    switch (self.status) {
        .starting => return "Waiting for game to start",
        .playing => switch (self.current_player) {
            .x => return "Player X turn",
            .o => return "Player O turn",
        },
        .hasWinner => switch (self.current_player) {
            .x => return "Player X won",
            .o => return "Player O won",
        },
        .stalemate => return "Stalemate",
    }
}
pub fn getStatusz(self: *GameState) [*:0]const u8 {
    switch (self.status) {
        .starting => return "Waiting for game to start",
        .playing => switch (self.current_player) {
            .x => return "Player X turn",
            .o => return "Player O turn",
        },
        .hasWinner => switch (self.current_player) {
            .x => return "Player X won",
            .o => return "Player O won",
        },
        .stalemate => return "Stalemate",
    }
}
// there are sideeffects provided on this.
// anytype is given to publish events and is_server is passed to

// events are processed by the state and it only modifies itself.
// it should also be able to emit events, albeit its dangerous
pub fn handleEvent(state: *GameState, ev: Event, publisher: anytype, is_server: bool) !void {
    // so this cant throw now... ouch
    switch (ev) {
        .gameCreated => return error.BadEvent,
        .__runtimeError => @panic("cannot pass __runtimeError into resolveEvent()"),
        .playerJoined => |data| {
            const index = @as(usize, @intFromEnum(data.side));
            assert(index <= 1);
            if (state.players[index] == null) {
                state.players[index] = data.playerId;
            } else {
                return error.PlayerOfThisSideAleadyJoined;
            }

            if (state.players[0] != null and state.players[1] != null) {
                state.status = .playing;
            }
        },
        .gameFinished => |data| {
            // blank event for traceability
            _ = data;
        },
        .moveMade => |data| {
            if (!state.can_play()) {
                return error.CantPlayYet;
            }
            const new_status = try state.handleMoveMadeEvent(data, publisher, is_server);
            state.status = new_status;

            const is_ai_move = true;

            if (is_ai_move) {
                if (is_server) {
                    // publish correct event only as a server. local play uses server mode
                    // PublisherUsage.publishEvent(publisher, .{});
                }
            }
        },
    }
}

fn handleMoveMadeEvent(state: *GameState, ev: Event.MoveMade, publisher: anytype, is_server: bool) !Status {
    _ = is_server;
    // cant use references
    if (state.status != .playing) {
        return error.GameFinished;
    }
    // check if its the correct player turn
    const player_side = ev.side;
    if (player_side != state.current_player) {
        return error.WrongSide;
    }

    const size = state.board.size;
    const pos = ev.position;

    if (pos.y >= size or pos.x >= size) {
        return error.InvalidPosition;
    }

    const selected = state.board.getValue(pos);
    if (selected != .empty) {
        return error.CannotSelectAlreadySelected;
    }

    state.board.setValue(pos, switch (player_side) {
        .x => .x,
        .o => .o,
    });

    const maybe_win = state.board.getWinCondition();

    if (maybe_win) |win| {
        state.status = .hasWinner;
        state.current_player = win.side;
        PublisherUsage.publishEvent(publisher, .{ .gameFinished = .{
            .outcome = if (win.side == .x) .xWon else .oWon,
        } });
    } else if (state.board.hasMovesAvailable()) {
        // switch the players
        state.current_player = player_side.other();
    } else {
        state.status = .stalemate;
        PublisherUsage.publishEvent(publisher, .{ .gameFinished = .{
            .outcome = .stalemate,
        } });
    }

    return state.status;
}

// test the state and only the state!
//
const TestPublisher = struct {
    values: std.BoundedArray(Event, 10) = std.BoundedArray(Event, 10){},

    pub fn onEvent(self: *@This(), ev: Event) void {
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

const testing = std.testing;

test "grid init" {
    // var publisher = TestPublisher{};
    var state = try GameState.init(
        testing.allocator,
        &[_]Event{
            .{
                .gameCreated = .{
                    .boardSize = 3,
                    .gameId = UUID.init(),
                },
            },
        },
    );
    defer state.deinit();

    try testing.expectEqual(.starting, state.status);
    try testing.expectEqual(.empty, state.board.getValue(.{ .x = 1, .y = 1 }));
}

test "player join + make move" {
    var publisher = TestPublisher{};
    var state = try GameState.init(
        testing.allocator,
        &[_]Event{
            .{ .gameCreated = .{
                .boardSize = 3,
                .gameId = UUID.init(),
            } },
            .{ .playerJoined = test_joinHumanX },
            .{ .playerJoined = test_joinHumanO },
        },
    );
    defer state.deinit();

    const is_server = true;

    try testing.expectEqual(.playing, state.status);
    try testing.expectEqual(.x, state.current_player);

    try state.handleEvent(.{ .moveMade = .{ .side = .x, .position = .{ .x = 2, .y = 1 } } }, &publisher, is_server);
    try testing.expectEqual(.playing, state.status);
    try testing.expectEqual(.o, state.current_player);

    try state.handleEvent(.{ .moveMade = .{ .side = .o, .position = .{ .x = 0, .y = 0 } } }, &publisher, is_server);
    try testing.expectEqual(.playing, state.status);
    try testing.expectEqual(.x, state.current_player);

    // try testing.expectEqualSlices(u8,
    //     \\o - -
    //     \\- - x
    //     \\- - -
    // , list.items);
}

test "common errors and errors" {
    var publisher = TestPublisher{};
    var state = try GameState.init(
        testing.allocator,
        &[_]Event{
            .{ .gameCreated = .{
                .boardSize = 3,
                .gameId = UUID.initFromNumber(9),
            } },
        },
    );
    defer state.deinit();

    const is_server = true;

    // cant move as no player joined
    try testing.expectError(error.CantPlayYet, state.handleEvent(.{
        .moveMade = .{ .side = .x, .position = .{ .x = 0, .y = 0 } },
    }, &publisher, is_server));

    try state.handleEvent(.{
        .playerJoined = .{ .playerId = .{ .human = UUID.init() }, .side = .x },
    }, &publisher, is_server);

    // cant move as only one player joined
    try testing.expectError(error.CantPlayYet, state.handleEvent(.{
        .moveMade = .{ .side = .x, .position = .{ .x = 0, .y = 0 } },
    }, &publisher, is_server));

    // cant join to already taken side
    try testing.expectError(error.PlayerOfThisSideAleadyJoined, state.handleEvent(.{
        .playerJoined = .{ .playerId = .{ .human = UUID.init() }, .side = .x },
    }, &publisher, is_server));

    try state.handleEvent(.{
        .playerJoined = .{ .playerId = .{ .human = UUID.init() }, .side = .o },
    }, &publisher, is_server);

    // cant play for the other side
    try testing.expectError(error.WrongSide, state.handleEvent(.{
        .moveMade = .{ .side = .o, .position = .{ .x = 0, .y = 0 } },
    }, &publisher, is_server));

    // play till win
    try state.handleEvent(.{
        .moveMade = .{ .side = .x, .position = .{ .x = 0, .y = 0 } },
    }, &publisher, is_server);

    try state.handleEvent(.{
        .moveMade = .{ .side = .o, .position = .{ .x = 1, .y = 0 } },
    }, &publisher, is_server);

    try state.handleEvent(.{
        .moveMade = .{ .side = .x, .position = .{ .x = 0, .y = 1 } },
    }, &publisher, is_server);

    try state.handleEvent(.{
        .moveMade = .{ .side = .o, .position = .{ .x = 1, .y = 1 } },
    }, &publisher, is_server);

    try state.handleEvent(.{
        .moveMade = .{ .side = .x, .position = .{ .x = 0, .y = 2 } },
    }, &publisher, is_server);

    // expect a gameFinished event
    try testing.expectEqual(Event{ .gameFinished = .{ .outcome = .xWon } }, publisher.values.get(0));
}
