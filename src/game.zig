const std = @import("std");
const Allocator = std.mem.Allocator;
const Ai = @import("ai.zig").Ai;
const CliGameHandler = @import("cli.zig").CliGameHandler;
const assert = std.debug.assert;
const testing_allocator = std.testing.allocator;
const testing = std.testing;
const ArrayList = std.ArrayList;

pub const GAME_SIZE = 3;
pub const STARTING_POSITION: CellPosition = .{ .x = 1, .y = 1 };

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

pub const Player = enum { X, O };

/// coordinates are x = right, y = down
pub const CellPosition = struct { x: usize, y: usize };

pub const CellValue = enum { Empty, X, O };

pub const State = struct {
    grid: [][]CellValue,
    size: usize,
    status: Status,

    pub fn init(
        allocator: Allocator,
        boardSize: usize,
    ) !State {
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
        return .{
            .grid = grid,
            .size = boardSize,
            .status = .TurnX,
        };
    }

    pub fn deinit(self: State, allocator: Allocator) void {
        for (self.grid) |row| {
            allocator.free(row);
        }
        allocator.free(self.grid);
    }

    pub fn makeMove(self: *State, pos: CellPosition) !Status {
        // try here?
        const newStatus = try self.makeMoveInternal(pos);
        self.status = newStatus;
        return newStatus;
    }

    fn makeMoveInternal(self: State, pos: CellPosition) !Status {
        if (self.status != .TurnX and self.status != .TurnO) {
            return error.GameFinished;
        }

        if (pos.y >= self.size or pos.x >= self.size) {
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

            if (count == @as(i8, @intCast(self.size))) return .WinX;
            if (count == -@as(i8, @intCast(self.size))) return .WinO;
        }

        //check horizontals
        for (0..self.size) |col| {
            var count: i8 = 0;
            for (0..self.size) |row| {
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
            if (count == @as(i8, @intCast(self.size))) return .WinX;
            if (count == -@as(i8, @intCast(self.size))) return .WinO;
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

    pub fn debugPrintWriter(self: State, writer: std.io.AnyWriter) !void {
        for (self.grid, 0..) |row, i| {
            for (row, 0..) |cell, j| {
                switch (cell) {
                    .Empty => try writer.writeAll("-"),
                    .X => try writer.writeAll("x"),
                    .O => try writer.writeAll("o"),
                }
                if (j < self.size - 1)
                    try writer.writeAll(" ");
            }
            if (i < self.size - 1)
                try writer.writeAll("\n");
        }
    }

    pub fn debugPrint(self: State) void {
        const print = std.debug.print;

        for (self.grid, 0..) |col, i| {
            for (col, 0..) |cell, j| {
                switch (cell) {
                    .Empty => print("-", .{}),
                    .X => print("x", .{}),
                    .O => print("o", .{}),
                }
                if (j < self.size - 1)
                    print(" ", .{});
            }
            if (i < self.size - 1)
                print("\n", .{});
        }
    }
};

test "grid init" {
    const state = try State.init(testing_allocator, 3);
    defer state.deinit(testing_allocator);

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
    var state = try State.init(testing_allocator, 3);
    defer state.deinit(testing_allocator);

    var list = ArrayList(u8).init(testing_allocator);
    defer list.deinit();

    try testing.expectEqual(.TurnX, state.status);

    // try expect((try state.makeMove(.{ .x = 1, .y = 1 })) == .TurnO);
    try testing.expectEqual(.TurnO, (try state.makeMove(.{ .x = 2, .y = 1 })));
    try testing.expectEqual(.TurnO, state.status);
    try testing.expectEqual(.TurnX, (try state.makeMove(.{ .x = 0, .y = 0 })));

    try state.debugPrintWriter(list.writer().any());

    try testing.expectEqualSlices(u8,
        \\o - -
        \\- - x
        \\- - -
    , list.items);
}

test "make move errors" {
    var state = try State.init(testing_allocator, 3);
    defer state.deinit(testing_allocator);

    try std.testing.expectError(error.InvalidPosition, state.makeMove(.{ .x = 3, .y = 1 }));

    _ = try state.makeMove(.{ .x = 1, .y = 1 });

    try std.testing.expectError(error.CannotSelectAlreadySelected, state.makeMove(.{ .x = 1, .y = 1 }));

    state.status = .Stalemate;

    try std.testing.expectError(error.GameFinished, state.makeMove(.{ .x = 1, .y = 1 }));
}

test "win condition horizontal" {
    var state = try State.init(testing_allocator, 3);
    defer state.deinit(testing_allocator);

    state.grid[0][0] = .X;
    state.grid[0][1] = .X;

    const status = try state.makeMove(.{ .x = 2, .y = 0 });

    try testing.expectEqual(.WinX, status);
}

test "win condition vertical" {
    var state = try State.init(testing_allocator, 3);
    defer state.deinit(testing_allocator);

    state.grid[0][0] = .X;
    state.grid[1][0] = .X;

    const status = try state.makeMove(.{ .x = 0, .y = 2 });

    try testing.expectEqual(.WinX, status);
}

test "win condition diagonal 1" {
    var state = try State.init(testing_allocator, 3);
    defer state.deinit(testing_allocator);

    state.grid[0][0] = .X;
    state.grid[1][1] = .X;

    const status = try state.makeMove(.{ .x = 2, .y = 2 });

    try testing.expectEqual(.WinX, status);
}

test "win condition diagonal 2" {
    var state = try State.init(testing_allocator, 3);
    defer state.deinit(testing_allocator);

    state.grid[0][2] = .X;
    state.grid[1][1] = .X;

    const status = try state.makeMove(.{ .x = 0, .y = 2 });

    try testing.expectEqual(.WinX, status);
}
