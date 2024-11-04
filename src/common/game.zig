const std = @import("std");
const vendor = @import("vendor");
const uuid = vendor.uuid;
const Allocator = std.mem.Allocator;
const Ai = @import("Ai.zig");
const assert = std.debug.assert;
const testing_allocator = std.testing.allocator;
const testing = std.testing;
const ArrayList = std.ArrayList;
const events = @import("events.zig");

/// specifies position of the cell
/// where coordinate 0,0 is at the top-left corner
/// x increments to the right
/// y increments down
pub const CellPosition = struct { x: usize, y: usize };

pub const CellValue = enum { Empty, X, O };

pub const Status = enum {
    Stalemate,
    TurnX,
    TurnO,
    WinX,
    WinO,

    pub fn isPlaying(self: Status) bool {
        return self == .TurnX or self == .TurnO;
    }
};

pub const PlayerSide = enum { X, O };

pub const GameMode = enum {
    withAi,
    multiplayer,
};

pub const ResolvedState = struct {
    grid: [][]CellValue,
    status: Status,

    mode: GameMode,
    ai: ?Ai.Difficulty,

    seqId: usize = 0,

    pub fn init(allocator: Allocator, startGameEvent: events.StartGameEvent) !ResolvedState {
        const boardSize = startGameEvent.boardSize();

        // startGameEvent.
        if (boardSize != 3) {
            return error.BoardSizeNotSupported;
        }

        const grid = try allocator.alloc([]CellValue, boardSize);
        for (grid) |*row| {
            row.* = try allocator.alloc(CellValue, boardSize);
            for (row.*) |*cell| {
                cell.* = .Empty;
            }
        }

        var ai: ?Ai.Difficulty = null;

        if (startGameEvent == .withAi) {
            ai = startGameEvent.withAi.aiDifficulty;
        }

        return .{
            .grid = grid,
            .status = .TurnX,
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
        // std.debug.print("deiniting resolved game state 1 {any} \n", .{self.grid});
        for (self.grid) |row| {
            allocator.free(row);
        }
        // std.debug.print("deiniting resolved game state 2 \n", .{});

        allocator.free(self.grid);
        // std.debug.print("deiniting resolved game state 3 \n", .{});
    }

    // i cant implement this because
    // error: expected type '*game.ResolvedState', found '*const game.ResolvedState'
    // fixed by not using it and drilling in
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

    fn handleMakeMoveEvent(self: *ResolvedState, pos: CellPosition) !Status {
        const size = self.grid.len;
        if (self.status != .TurnX and self.status != .TurnO) {
            return error.GameFinished;
        }

        if (pos.y >= size or pos.x >= size) {
            return error.InvalidPosition;
        }

        const selected = self.grid[pos.y][pos.x];
        if (selected != .Empty) {
            return error.CannotSelectAlreadySelected;
        }

        // mutate the grid
        switch (self.status) {
            .TurnX => self.grid[pos.y][pos.x] = .X,
            .TurnO => self.grid[pos.y][pos.x] = .O,
            else => unreachable,
        }

        //check verticals
        for (self.grid) |col| {
            var count: i8 = 0;

            for (col) |cell| {
                switch (cell) {
                    .Empty => {
                        count = 0;
                        continue;
                    },
                    .X => count += 1,
                    .O => count -= 1,
                }
            }

            if (count == @as(i8, @intCast(size))) return .WinX;
            if (count == -@as(i8, @intCast(size))) return .WinO;
        }

        //check horizontals
        for (0..size) |col| {
            var count: i8 = 0;
            for (0..size) |row| {
                const cell = self.grid[row][col];
                switch (cell) {
                    .Empty => {
                        count = 0;
                        continue;
                    },
                    .X => count += 1,
                    .O => count -= 1,
                }
            }
            // not allowed!
            if (count == @as(i8, @intCast(size))) return .WinX;
            if (count == -@as(i8, @intCast(size))) return .WinO;
        }

        // check diagonals
        // TODO: hardcoded to 3x3
        if (self.grid[1][1] == .X or self.grid[1][1] == .O) {
            if ((self.grid[0][0] == self.grid[1][1] and self.grid[1][1] == self.grid[2][2]) or
                (self.grid[0][2] == self.grid[1][1] and self.grid[1][1] == self.grid[2][0]))
            {
                switch (self.grid[1][1]) {
                    .X => return .WinX,
                    .O => return .WinO,
                    else => unreachable,
                }
            }
        }

        // check if there are available moves
        for (self.grid) |row| {
            for (row) |cell| {
                if (cell == .Empty) {
                    switch (self.status) {
                        .TurnX => return .TurnO,
                        .TurnO => return .TurnX,
                        else => unreachable,
                    }
                }
            }
        }

        return .Stalemate;
    }

    pub fn debugPrint(self: *ResolvedState) void {
        const print = std.debug.print;
        const size = self.grid.len;

        for (self.grid, 0..) |col, i| {
            for (col, 0..) |cell, j| {
                switch (cell) {
                    .Empty => print("-", .{}),
                    .X => print("x", .{}),
                    .O => print("o", .{}),
                }
                if (j < size - 1)
                    print(" ", .{});
            }
            if (i < size - 1)
                print("\n", .{});
        }
    }

    pub fn debugPrintWriter(self: *ResolvedState, writer: std.io.AnyWriter) !void {
        const size = self.grid.len;
        for (self.grid, 0..) |row, i| {
            for (row, 0..) |cell, j| {
                switch (cell) {
                    .Empty => try writer.writeAll("-"),
                    .X => try writer.writeAll("x"),
                    .O => try writer.writeAll("o"),
                }
                if (j < size - 1)
                    try writer.writeAll(" ");
            }
            if (i < size - 1)
                try writer.writeAll("\n");
        }
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

test "grid init" {
    var state = try ResolvedState.init(testing_allocator, .{ .multiplayer = .{
        .boardSize = 3,
        .playerSide = .X,
    } });
    defer state.deinit(testing_allocator);

    try testing.expectEqual(0, state.seqId);

    // good example of how to mock a writer
    var list = ArrayList(u8).init(testing_allocator);
    defer list.deinit();

    try state.debugPrintWriter(list.writer().any());
    try testing.expectEqualSlices(u8,
        \\- - -
        \\- - -
        \\- - -
    , list.items);
}

test "make move" {
    var state = try ResolvedState.init(testing_allocator, .{ .multiplayer = .{
        .boardSize = 3,
        .playerSide = .X,
    } });
    defer state.deinit(testing_allocator);
    try testing.expectEqual(.TurnX, state.status);

    try state.resolveEvent(events.Event{ .makeMove = .{ .position = .{ .x = 2, .y = 1 } } });
    try testing.expectEqual(1, state.seqId);
    try testing.expectEqual(.TurnO, state.status);

    try state.resolveEvent(events.Event{ .makeMove = .{ .position = .{ .x = 0, .y = 0 } } });
    try testing.expectEqual(2, state.seqId);
    try testing.expectEqual(.TurnX, state.status);

    var list = ArrayList(u8).init(testing_allocator);
    defer list.deinit();

    try state.debugPrintWriter(list.writer().any());

    try testing.expectEqualSlices(u8,
        \\o - -
        \\- - x
        \\- - -
    , list.items);
}

test "make move errors" {
    var state = try ResolvedState.init(testing_allocator, .{ .multiplayer = .{
        .boardSize = 3,
        .playerSide = .X,
    } });
    defer state.deinit(testing_allocator);

    try std.testing.expectError(error.InvalidPosition, state.resolveEvent(.{ .makeMove = .{ .position = .{ .x = 3, .y = 1 } } }));
    try testing.expectEqual(0, state.seqId);
    try state.resolveEvent(.{ .makeMove = .{ .position = .{ .x = 1, .y = 1 } } });

    try std.testing.expectError(error.CannotSelectAlreadySelected, state.resolveEvent(.{ .makeMove = .{ .position = .{ .x = 1, .y = 1 } } }));

    state.status = .Stalemate;

    try std.testing.expectError(error.GameFinished, state.resolveEvent(.{ .makeMove = .{ .position = .{ .x = 1, .y = 1 } } }));
}

// test "win condition horizontal" {
//     var gameEvents = ArrayList(events.Event).init(testing_allocator);
//     defer gameEvents.deinit();

//     gameEvents.insertSlice(0, [_]events.Event{});

//     var state = try ResolvedState.initAndResolveAll(testing_allocator, gameEvents);
//     defer state.deinit(testing_allocator);

//     state.grid[0][0] = .X;
//     state.grid[0][1] = .X;

//     const status = try state.makeMove(.{ .x = 2, .y = 0 });

//     try testing.expectEqual(.WinX, status);
// }

test "win condition horizontal" {
    var state = try ResolvedState.init(testing_allocator, .{ .multiplayer = .{
        .boardSize = 3,
        .playerSide = .X,
    } });
    defer state.deinit(testing_allocator);

    state.grid[0][0] = .X;
    state.grid[0][1] = .X;
    try state.resolveEvent(.{ .makeMove = .{ .position = .{ .x = 2, .y = 0 } } });

    try testing.expectEqual(.WinX, state.status);
}

test "win condition vertical" {
    var state = try ResolvedState.init(testing_allocator, .{ .multiplayer = .{
        .boardSize = 3,
        .playerSide = .X,
    } });
    defer state.deinit(testing_allocator);

    state.grid[0][0] = .X;
    state.grid[1][0] = .X;
    try state.resolveEvent(.{ .makeMove = .{ .position = .{ .x = 0, .y = 2 } } });

    try testing.expectEqual(.WinX, state.status);
}

// test "win condition diagonal 1" {
//     var state = try State.init(testing_allocator, 3);
//     defer state.deinit(testing_allocator);

//     state.grid[0][0] = .X;
//     state.grid[1][1] = .X;

//     const status = try state.makeMove(.{ .x = 2, .y = 2 });

//     try testing.expectEqual(.WinX, status);
// }

// test "win condition diagonal 2" {
//     var state = try State.init(testing_allocator, 3);
//     defer state.deinit(testing_allocator);

//     state.grid[0][2] = .X;
//     state.grid[1][1] = .X;

//     const status = try state.makeMove(.{ .x = 0, .y = 2 });

//     try testing.expectEqual(.WinX, status);
// }
