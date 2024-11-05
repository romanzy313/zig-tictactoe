const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const math = std.math;
const ArrayList = std.ArrayList;
const json = std.json;

const WinCondition = @import("WinCondition.zig");

const max_board_size = 50;

/// specifies position of the cell
/// where coordinate 0,0 is at the top-left corner
/// x increments to the right
/// y increments down
pub const CellPosition = struct { x: usize, y: usize };

pub const CellValue = enum { Empty, X, O };

const Board = @This();

// this is done here, so that in the future its value could be serialize compressed!
// in json that would look like "-----xxxo", where size is inferred. scanned row by row
// binary can pack it even more: something like 5-3xo: [3](u14 + u2), with maximum overall length of 16383. LRU its called?
grid: [][]CellValue,
size: usize,

pub fn initEmpty(allocator: Allocator, size: usize) !Board {
    if (!isSizeValid(size)) {
        return error.InvalidBoardSize;
    }

    const grid = try allocator.alloc([]CellValue, size);
    for (grid) |*row| {
        row.* = try allocator.alloc(CellValue, size);
        for (row.*) |*cell| {
            cell.* = .Empty;
        }
    }

    return .{
        .grid = grid,
        .size = size,
    };
}

pub fn deinit(self: *Board, allocator: Allocator) void {
    for (self.grid) |row| {
        allocator.free(row);
    }

    allocator.free(self.grid);
}

/// make sure that in runtime the position was checked to be within the board size
/// or should I check this here?
pub fn getValue(self: *Board, pos: CellPosition) CellValue {
    assert(pos.x < self.size);
    assert(pos.y < self.size);

    return self.grid[pos.y][pos.x];
}

/// make sure that in runtime the position was checked to be within the board size
pub fn setValue(self: *Board, pos: CellPosition, value: CellValue) void {
    // debug assers
    assert(pos.x < self.size);
    assert(pos.y < self.size);

    self.grid[pos.y][pos.x] = value;
}

pub fn hasMovesAvailable(self: *Board) bool {
    for (self.grid) |row| {
        for (row) |cell| {
            if (cell == .Empty) {
                return true;
            }
        }
    }

    return false;
}

pub fn getWinCondition(self: *Board) ?WinCondition {
    return WinCondition.check(self.grid);
}

/// serializes the value as string. The caller is responsible for clearing it!
/// this should not be used, as writer should be used instead (and is used for json)
pub fn serialize(self: *Board, allocator: Allocator) ![]const u8 {
    // do serialization
    // const b_array = try BoundedArray(u8, self.size).init(0);
    var list = try ArrayList(u8).initCapacity(allocator, self.size * self.size);

    for (self.grid) |row| {
        for (row) |cell| {
            switch (cell) {
                .Empty => list.appendAssumeCapacity('-'),
                .X => list.appendAssumeCapacity('x'),
                .O => list.appendAssumeCapacity('o'),
            }
        }
    }

    const slice = try list.toOwnedSlice();
    return slice;
}

pub fn parseFromSlice(allocator: Allocator, slice: []const u8) !Board {
    const size = try perfectSquare(slice.len);

    if (!isSizeValid(size)) {
        return error.InvalidBoardSize;
    }

    for (slice) |v| {
        switch (v) {
            '-', 'x', 'o' => continue,
            else => return error.InvalidCharacter,
        }
    }

    const grid = try allocator.alloc([]CellValue, size);
    for (grid, 0..) |*row, y| {
        row.* = try allocator.alloc(CellValue, size);
        for (row.*, 0..) |*cell, x| {
            const v = slice[x + size * y];
            cell.* = switch (v) {
                '-' => .Empty,
                'x' => .X,
                'o' => .O,
                else => unreachable,
            };
        }
    }

    return .{
        .grid = grid,
        .size = size,
    };
}

pub fn jsonStringify(self: Board, out_writer: anytype) !void {
    // size could reach 50*50!
    const hacky_size = 10 * 10;

    if (self.size * self.size > hacky_size) {
        std.log.err("the board is too large: {d}\n", .{self.size});
        return error.OutOfMemory; // not really what has happened, but cant return any other error
    }
    var hack = std.BoundedArray(u8, hacky_size).init(0) catch unreachable;

    for (self.grid) |row| {
        for (row) |cell| {
            switch (cell) {
                .Empty => _ = hack.append('-') catch unreachable, // not nice either
                .X => _ = hack.append('x') catch unreachable,
                .O => _ = hack.append('o') catch unreachable,
            }
        }
    }
    try out_writer.print("\"{s}\"", .{hack.slice()});
}

// hmm how can i do this without an allocator?
pub fn jsonStringifyIdeal(self: Board, out_writer: anytype) !void {
    try out_writer.valueStart();
    try out_writer.writeByte('"');

    for (self.grid) |row| {
        for (row) |cell| {
            switch (cell) {
                .Empty => _ = try out_writer.writeByte('-'),
                .X => _ = try out_writer.writeByte('x'),
                .O => _ = try out_writer.writeByte('o'),
            }
        }
    }
    _ = try out_writer.writeByte('"');

    out_writer.valueDone();
}

pub fn jsonParse(
    allocator: Allocator,
    source: anytype,
    _: json.ParseOptions,
) !Board {
    switch (try source.nextAlloc(allocator, .alloc_if_needed)) {
        .string, .allocated_string => |value| {
            return parseFromSlice(allocator, value) catch error.InvalidCharacter;
        },
        else => return error.UnexpectedToken,
    }
}

pub fn debugPrint(self: *Board) void {
    const print = std.debug.print;

    for (self.grid) |row| {
        for (row) |cell| {
            switch (cell) {
                .Empty => print("-", .{}),
                .X => print("x", .{}),
                .O => print("o", .{}),
            }
            print(" ", .{});
        }
        print("\n", .{});
    }
}

pub fn makeTestBoardStatic(comptime size: usize, staticVal: [size][size]CellValue) type {
    return struct {
        fn withAllocator(allocator: Allocator) Board {
            const grid = initEmpty(allocator, size) catch unreachable;

            for (grid.grid, 0..) |*row, x| {
                for (row.*, 0..) |*cell, y| {
                    cell.* = staticVal[x][y];
                }
            }

            return grid;
        }
    };
}

fn isSizeValid(size: usize) bool {
    // temporary
    if (size != 3) {
        std.debug.print("board sizes of not 3 are not supported! \n", .{});
        return false;
    }

    return size >= 3 and size <= max_board_size;
}

/// checks for perfect square
/// something like this in stdlib maybe? https://stackoverflow.com/questions/295579/fastest-way-to-determine-if-an-integers-square-root-is-an-integer
fn perfectSquare(x: usize) !usize {
    if (x < 4) {
        return error.NotPerfectSquare;
    }

    const ans = math.sqrt(x);

    if (ans * ans != x) {
        return error.NotPerfectSquare;
    }

    return ans;
}

test perfectSquare {
    try testing.expectEqual(3, perfectSquare(9));
    try testing.expectEqual(4, perfectSquare(16));
    try testing.expectError(error.NotPerfectSquare, perfectSquare(10));
    try testing.expectError(error.NotPerfectSquare, perfectSquare(15));
}

test initEmpty {
    var grid = try Board.initEmpty(testing.allocator, 3);
    defer grid.deinit(testing.allocator);

    try testing.expectEqual(3, grid.size);
}

test serialize {
    const staticVal = [3][3]CellValue{
        [_]CellValue{ .Empty, .Empty, .Empty },
        [_]CellValue{ .Empty, .X, .O },
        [_]CellValue{ .Empty, .Empty, .Empty },
    };
    var grid = makeTestBoardStatic(3, staticVal).withAllocator(testing.allocator);
    defer grid.deinit(testing.allocator);

    const serialized = try grid.serialize(testing.allocator);
    defer testing.allocator.free(serialized);

    try testing.expectEqualStrings("----xo---", serialized);
}

test parseFromSlice {
    var okGrid = try parseFromSlice(testing.allocator, "----xo---");
    defer okGrid.deinit(testing.allocator);

    try testing.expectEqual(.Empty, okGrid.grid[0][0]);
    try testing.expectEqual(.X, okGrid.grid[1][1]);
    try testing.expectEqual(.O, okGrid.grid[1][2]);

    // now check bad inputs
    try testing.expectError(error.NotPerfectSquare, parseFromSlice(testing.allocator, "-----"));
    try testing.expectError(error.InvalidCharacter, parseFromSlice(testing.allocator, "----zo---"));
}

test "jsonification" {
    const T = struct { board: Board };

    const staticVal = [3][3]CellValue{
        [_]CellValue{ .Empty, .Empty, .Empty },
        [_]CellValue{ .Empty, .X, .O },
        [_]CellValue{ .Empty, .Empty, .Empty },
    };
    var grid = makeTestBoardStatic(3, staticVal).withAllocator(testing.allocator);
    defer grid.deinit(testing.allocator);

    const value = T{
        .board = grid,
    };

    const res = try std.json.stringifyAlloc(testing.allocator, value, .{});
    defer testing.allocator.free(res);

    try testing.expectEqualStrings("{\"board\":\"----xo---\"}", res);
    const parse = try json.parseFromSlice(
        T,
        testing.allocator,
        res,
        .{},
    );
    defer parse.deinit();

    try testing.expectEqualDeep(value, parse.value);
}

test makeTestBoardStatic {
    const staticVal = [3][3]CellValue{
        [_]CellValue{ .Empty, .Empty, .Empty },
        [_]CellValue{ .Empty, .X, .O },
        [_]CellValue{ .Empty, .Empty, .Empty },
    };
    var grid = makeTestBoardStatic(3, staticVal).withAllocator(testing.allocator);
    defer grid.deinit(testing.allocator);

    try testing.expectEqual(.Empty, grid.grid[0][0]);
    try testing.expectEqual(.X, grid.grid[1][1]);
    try testing.expectEqual(.O, grid.grid[1][2]);
}
