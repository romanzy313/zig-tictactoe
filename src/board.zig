const std = @import("std");

// pub fn mockGrid(state: *const []*const []Board.CellState) [][]Board.CellState {

// }
pub const Grid = [][]Board.CellState;

fn allocGrid(alloc: std.mem.Allocator, size: usize) !Grid {
    const grid = try alloc.alloc([]Board.CellState, size);
    for (grid) |*row| {
        row.* = try alloc.alloc(Board.CellState, size);
        for (row.*) |*cell| {
            cell.* = Board.CellState.Empty;
        }
    }
    return grid;
}

// uuuggghhh
// fn gridFromJson(alloc: std.mem.Allocator, payload: []const u8) !Grid {
//     const parsed = try std.json.parseFromSlice(
//         [][]Board.CellState,
//         alloc,
//         payload,
//         .{},
//     );
//     defer parsed.deinit();
//     return parsed.value;
// }

fn deallocGrid(alloc: std.mem.Allocator, grid: [][]Board.CellState) !void {
    // Deallocate the grid memory
    for (grid) |row| {
        alloc.free(row);
    }
    alloc.free(grid);
}

pub const Board = struct {
    pub const CellState = enum { Empty, X, O };
    pub const CellPosition = struct { x: usize, y: usize };
    pub const Player = enum { X, O };
    pub const State = enum { Playing, Stalemate, WinX, WinO };

    alloc: std.mem.Allocator,
    grid: Grid,
    size: usize, // Store the size of the board for easier access

    // Dynamically allocate/deallocate the grid to the given size
    fn allocGrid(alloc: std.mem.Allocator, size: usize) ![][]CellState {
        const grid = try alloc.alloc([]CellState, size);
        for (grid) |*row| {
            row.* = try alloc.alloc(CellState, size);
            for (row.*) |*cell| {
                cell.* = CellState.Empty;
            }
        }
        return grid;
    }

    pub fn deinit(self: *Board) void {
        // Deallocate the grid memory
        for (self.grid) |row| {
            self.alloc.free(row);
        }
        self.alloc.free(self.grid);
    }

    pub fn init(alloc: std.mem.Allocator, size: usize) !Board {
        return Board{
            .alloc = alloc,
            .grid = try Board.allocGrid(alloc, size),
            .size = size,
        };
    }

    // Optional: Initialize the board with an existing grid (for testing purposes)
    pub fn initWithGrid(alloc: std.mem.Allocator, grid: [][]CellState) !Board {
        return Board{
            .alloc = alloc,
            .grid = grid,
            .size = grid.len,
        };
    }

    pub fn state(self: *Board) State {
        // need to check 3 in a row. That means need to check every row and every corner + diagonals
        const boardSize = self.grid.len;
        //check verticals
        for (self.grid) |row| {
            var count: i8 = 0;

            for (row) |cell| {
                switch (cell) {
                    CellState.Empty => break,
                    CellState.X => {
                        count = count + 1;
                    },
                    CellState.O => {
                        count = count - 1;
                    },
                }
            }

            if (count == @as(i8, @intCast(boardSize))) return State.WinX;
            if (count == -@as(i8, @intCast(boardSize))) return State.WinO;
        }

        //check horizontals
        // the end index is included!
        for (0..boardSize) |col| {
            var count: i8 = 0;
            for (0..boardSize) |row| {
                const cell = self.grid[row][col];
                // std.debug.print("CELL STATE {any}. row = {d}, col = {d}\n", .{ cell, row, col });
                switch (cell) {
                    CellState.Empty => break,
                    CellState.X => {
                        count += 1;
                    },
                    CellState.O => {
                        count -= 1;
                    },
                }
            }
            switch (count) {
                3 => return State.WinX,
                -3 => return State.WinO,
                else => {},
            }
        }

        // check diagonals (hardcoded to 3x3 for now)

        if (self.grid[1][1] == CellState.X or self.grid[1][1] == CellState.O) {
            if ((self.grid[0][0] == self.grid[1][1] and self.grid[1][1] == self.grid[2][2]) or
                (self.grid[2][0] == self.grid[1][1] and self.grid[1][1] == self.grid[0][2]))
            {
                switch (self.grid[1][1]) {
                    CellState.X => return State.WinX,
                    CellState.O => return State.WinO,
                    else => unreachable,
                }
            }
        }

        // check if there are available moves
        for (self.grid) |row| {
            for (row) |cell| {
                if (cell == CellState.Empty) {
                    return State.Playing;
                }
            }
        }

        return State.Stalemate;
    }

    // This does move by mutating self!
    pub fn makeMove(self: *Board, player: Player, position: CellPosition) !void {
        const boardSize = self.grid.len;

        const row = position.x;
        const col = position.y;

        // Bounds checking
        if (row >= boardSize or col >= boardSize) {
            return error.InvalidPosition;
        }

        // Already selected checking
        const selected = self.grid[row][col];
        if (selected != CellState.Empty) {
            return error.CannotSelectAlreadySelected;
        }

        // Make the move
        switch (player) {
            Player.X => self.grid[row][col] = CellState.X,
            Player.O => self.grid[row][col] = CellState.O,
        }
    }

    pub fn print(self: Board, writer: std.io.AnyWriter) !void {
        for (self.grid, 0..) |row, i| {
            for (row, 0..) |cell, j| {
                switch (cell) {
                    CellState.Empty => try writer.writeAll("-"),
                    CellState.X => try writer.writeAll("x"),
                    CellState.O => try writer.writeAll("o"),
                }
                if (j < self.size - 1)
                    try writer.writeAll(" ");
            }
            if (i < self.size - 1)
                try writer.writeAll("\n");
        }
    }

    pub fn printWithSelection(self: *Board, writer: anytype, pos: CellPosition) !void {

        // https://stackoverflow.com/questions/4842424/list-of-ansi-color-escape-sequences
        const ansiNormal: []const u8 = "\u{001b}[0m";
        const ansiSelected: []const u8 = "\u{001b}[7m";

        // index capture syntax :(
        for (&self.grid, 0..) |*row, i| {
            for (row, 0..) |cell, j| {
                const ansiPrefix: []const u8 = if (pos.x == i and pos.y == j) ansiSelected else ansiNormal;
                switch (cell) {
                    CellState.Empty => try writer.print("{s}-{s}", .{ ansiPrefix, ansiNormal }),
                    CellState.X => try writer.print("{s}x{s}", .{ ansiPrefix, ansiNormal }),
                    CellState.O => try writer.print("{s}o{s}", .{ ansiPrefix, ansiNormal }),
                }
                try writer.writeAll(" ");
            }
            try writer.writeAll("\n");
        }
        // writer.flush();
    }
};

// Tests

const ArrayList = std.ArrayList;
const test_allocator = std.testing.allocator;
const expect = std.testing.expect;

test "Board prints correctly" {
    var list = ArrayList(u8).init(test_allocator);
    defer list.deinit();

    var board = try Board.init(test_allocator, 3);
    defer board.deinit();

    board.grid[0][0] = .X;
    board.grid[1][1] = .O;
    board.grid[2][2] = .X;

    try board.print(list.writer().any());
    try std.testing.expectEqualSlices(u8,
        \\x - -
        \\- o -
        \\- - x
    , list.items);
}

// this works atleast...
test "json parse raw" {
    const parsed = try std.json.parseFromSlice(
        [][]Board.CellState,
        test_allocator,
        \\[ [0,1,2], [0,0,0], [0,0,0] ]
    ,
        .{},
    );
    defer parsed.deinit();

    const grid = parsed.value;

    try expect(grid[0][0] == .Empty);
    try expect(grid[0][1] == .X);
    try expect(grid[0][2] == .O);
}
// test "json parse helper" {
//     const payload: []const u8 =
//         \\[ [0,1,2], [0,0,0], [0,0,0] ]
//     ;
//     const grid = try gridFromJson(test_allocator, payload);
//     try expect(grid[0][0] == .Empty);
//     try expect(grid[0][1] == .X);
//     try expect(grid[0][2] == .O);
// }

// still have no idea how to do this.
// how to define 2d array statically without fuss
// test "Board can be initialized with an existing grid" {
//     // const grid = [_][]Board.CellState{
//     //     &[_]Board.CellState{ .X, .Empty, .Empty },
//     //     &[_]Board.CellState{ .Empty, .O, .Empty },
//     //     &[_]Board.CellState{ .Empty, .Empty, .X },
//     // };

//     const grid = try allocGrid(test_allocator, 3);

//     var board = Board{
//         .alloc = test_allocator,
//         .grid = grid,
//         .size = 3,
//     };
//     defer board.deinit();

//     try expect(board.grid[0][0] == .X);
//     try expect(board.grid[1][1] == .O);
//     try expect(board.grid[2][2] == .X);
// }

test "WinCondition - vertical" {
    var board = try Board.init(test_allocator, 3);
    defer board.deinit();

    try std.testing.expectEqual(Board.State.None, board.state());

    // add a winning condition manually
    try board.makeMove(Board.Player.X, Board.CellPosition{ .x = 1, .y = 0 });
    try board.makeMove(Board.Player.X, Board.CellPosition{ .x = 1, .y = 1 });
    try board.makeMove(Board.Player.X, Board.CellPosition{ .x = 1, .y = 2 });

    try std.testing.expectEqual(Board.State.WinX, board.state());
}

// TODO these
// test "WinCondition - horizontal" {
//     const allocator = std.testing.allocator;
//     var board = Board.init(allocator);

//     try std.testing.expectEqual(GameStatus.None, board.condition());

//     // add a winning condition manually
//     try board.makeMove(Player.O, Position{ .x = 0, .y = 1 });
//     try board.makeMove(Player.O, Position{ .x = 1, .y = 1 });
//     try board.makeMove(Player.O, Position{ .x = 2, .y = 1 });

//     try std.testing.expectEqual(GameStatus.WinO, board.condition());
// }

// test "WinCondition - diagonals" {
//     const allocator = std.testing.allocator;
//     var board = Board{ .alloc = allocator, .grid = .{
//         [3]CellState{ .X, .Empty, .Empty },
//         [3]CellState{ .Empty, .X, .Empty },
//         [3]CellState{ .Empty, .Empty, .X },
//     }, .size = 3 };

//     try std.testing.expectEqual(GameStatus.WinX, board.condition());

//     // is this okay?
//     board.grid = .{
//         [_]CellState{ .Empty, .Empty, .O },
//         [_]CellState{ .Empty, .O, .Empty },
//         [_]CellState{ .O, .Empty, .Empty },
//     };

//     try std.testing.expectEqual(GameStatus.WinO, board.condition());
// }

// test "WinCondition - stalemate" {
//     const allocator = std.testing.allocator;
//     var board = Board{ .alloc = allocator, .grid = .{
//         [_]CellState{ .X, .X, .O },
//         [_]CellState{ .O, .X, .X },
//         [_]CellState{ .X, .O, .O },
//     }, .size = 3 };

//     try std.testing.expectEqual(GameStatus.Stalemate, board.condition());
// }
