const std = @import("std");
const uuid = @import("uuid");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const testing_allocator = std.testing.allocator;
const testing = std.testing;
const ArrayList = std.ArrayList;

const Board = @import("Board.zig");
const Ai = @import("Ai.zig");
const events = @import("events.zig");

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

pub const PlayerSide = enum { x, o };

pub const GameMode = enum {
    withAi,
    multiplayer,
};

pub const ResolvedState = struct {
    seqId: usize = 0, // for ordering of the events

    board: Board,
    status: Status,

    mode: GameMode,
    ai: ?Ai.Difficulty,

    // init must take in an array of events
    // must not pass the first event explicitly
    // so it is totally possible for there to be no board present?
    pub fn init(allocator: Allocator, startGameEvent: events.StartGameEvent) !ResolvedState {
        const board = try Board.initEmpty(allocator, startGameEvent.boardSize());

        var ai: ?Ai.Difficulty = null;

        if (startGameEvent == .withAi) {
            ai = startGameEvent.withAi.aiDifficulty;
        }

        return .{
            .board = board,
            .status = .turnX,
            .mode = startGameEvent.gameMode(),
            .ai = ai,
        };
    }

    // should events be owned slice (aka []const event.Event?)
    pub fn initAndResolveAll(allocator: Allocator, evs: []events.Event) !ResolvedState {
        // const self = init(allocator)

        if (evs.len == 0) {
            return error.BadEventCount;
        }

        if (evs[0] != .startGame) {
            return error.BadEvent;
        }

        const self = try init(allocator, evs[0].startGame);

        for (evs[1..]) |ev| {
            try self.resolveEvent(ev);
        }
        return self;
    }

    pub fn deinit(self: *ResolvedState, allocator: Allocator) void {
        self.board.deinit(allocator);
    }

    // TODO: why cant I implement this without self: *const ResolvedState?
    // error: expected type '*game.ResolvedState', found '*const game.ResolvedState'
    // fixed by not using it and doing a nested call instead
    // pub fn isGameOver(self: *ResolvedState) bool {
    //     return !self.status.isPlaying();
    // }

    pub fn resolveEvent(self: *ResolvedState, ev: events.Event) !void {
        switch (ev) {
            .startGame => return error.BadEvent,
            .makeMove => |moveEv| {
                const newStatus = try self.handleMakeMoveEvent(moveEv.position);
                self.status = newStatus;
            },
        }

        self.seqId += 1;
    }

    fn handleMakeMoveEvent(self: *ResolvedState, pos: Board.CellPosition) !Status {
        const size = self.board.size;
        if (self.status != .turnX and self.status != .turnO) {
            return error.GameFinished;
        }

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

        // check win condition

        const maybe_win_condition = self.board.getWinCondition();

        if (maybe_win_condition) |win| {
            switch (win.side) {
                .x => return .winX,
                .o => return .winO,
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

        return .stalemate;
    }
};

/// This is an object that persists on the server while the game is played
/// It is reponsible for:
/// - resolving current state
/// - serializing event streams
/// - forward it to connected players?,
/// - creating sideeffects (like issueing game over events?)
pub const StatefullTicTacToe = struct {
    //
};

pub const PlayerId = uuid.UUID;
pub const PlayerKind = enum { human, ai };
// trying to follow this https://nathancraddock.com/blog/zig-naming-conventions/

pub const AnyPlayer = struct {
    id: PlayerId,
    kind: PlayerKind,

    // allow any initialization here, with a given kind

    pub fn random(kind: PlayerKind) AnyPlayer {
        return .{
            .id = uuid.newV4(),
            .kind = kind,
        };
    }
};

pub const GamePlayers = struct {
    x: AnyPlayer,
    o: AnyPlayer,
};

// pub fn makeTestGrid(allocator: Allocator) [][]CellValue {
//     const grid = try allocator.alloc([]CellValue, boardSize);
//     for (grid) |*row| {
//         row.* = try allocator.alloc(CellValue, boardSize);
//         for (row.*) |*cell| {
//             cell.* = .Empty;
//         }
//     }
//     //
// }

test "grid init" {
    var state = try ResolvedState.init(testing_allocator, .{ .multiplayer = .{
        .boardSize = 3,
        .playerSide = .x,
    } });
    defer state.deinit(testing_allocator);

    try testing.expectEqual(0, state.seqId);

    // good example of how to mock a writer
    // var list = ArrayList(u8).init(testing_allocator);
    // defer list.deinit();

    // try state.debugPrintWriter(list.writer().any());
    // try testing.expectEqualSlices(u8,
    //     \\- - -
    //     \\- - -
    //     \\- - -
    // , list.items);
}

test "make move" {
    var state = try ResolvedState.init(testing_allocator, .{ .multiplayer = .{
        .boardSize = 3,
        .playerSide = .x,
    } });
    defer state.deinit(testing_allocator);
    try testing.expectEqual(.turnX, state.status);

    try state.resolveEvent(events.Event{ .makeMove = .{ .position = .{ .x = 2, .y = 1 } } });
    try testing.expectEqual(1, state.seqId);
    try testing.expectEqual(.turnO, state.status);

    try state.resolveEvent(events.Event{ .makeMove = .{ .position = .{ .x = 0, .y = 0 } } });
    try testing.expectEqual(2, state.seqId);
    try testing.expectEqual(.turnX, state.status);

    // removed
    // var list = ArrayList(u8).init(testing_allocator);
    // defer list.deinit();

    // try state.debugPrintWriter(list.writer().any());

    // try testing.expectEqualSlices(u8,
    //     \\o - -
    //     \\- - x
    //     \\- - -
    // , list.items);
}

test "make move errors" {
    var state = try ResolvedState.init(testing_allocator, .{ .multiplayer = .{
        .boardSize = 3,
        .playerSide = .x,
    } });
    defer state.deinit(testing_allocator);

    try std.testing.expectError(error.InvalidPosition, state.resolveEvent(.{ .makeMove = .{ .position = .{ .x = 3, .y = 1 } } }));
    try testing.expectEqual(0, state.seqId);
    try state.resolveEvent(.{ .makeMove = .{ .position = .{ .x = 1, .y = 1 } } });

    try std.testing.expectError(error.CannotSelectAlreadySelected, state.resolveEvent(.{ .makeMove = .{ .position = .{ .x = 1, .y = 1 } } }));

    state.status = .stalemate;

    try std.testing.expectError(error.GameFinished, state.resolveEvent(.{ .makeMove = .{ .position = .{ .x = 1, .y = 1 } } }));
}
