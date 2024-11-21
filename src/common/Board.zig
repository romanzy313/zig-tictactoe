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

pub const CellValue = enum { empty, x, o };

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
            cell.* = .empty;
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
///
/// Also, why is const okay? since I am not mutating it?
pub fn getValue(self: *const Board, pos: CellPosition) CellValue {
    assert(pos.x < self.size);
    assert(pos.y < self.size);

    return self.grid[pos.y][pos.x];
}

/// make sure that in runtime the position was checked to be within the board size
///
/// What why does `self: *const Board` still makes this work? I dont follow
/// This is mutation, i better protect it by making it "non-const?"
pub fn setValue(self: *Board, pos: CellPosition, value: CellValue) void {
    // debug assers
    assert(pos.x < self.size);
    assert(pos.y < self.size);

    self.grid[pos.y][pos.x] = value;
}

pub fn hasMovesAvailable(self: *Board) bool {
    for (self.grid) |row| {
        for (row) |cell| {
            if (cell == .empty) {
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
    var list = try ArrayList(u8).initCapacity(allocator, self.size * self.size);

    for (self.grid) |row| {
        for (row) |cell| {
            switch (cell) {
                .empty => list.appendAssumeCapacity('-'),
                .x => list.appendAssumeCapacity('x'),
                .o => list.appendAssumeCapacity('o'),
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
                '-' => .empty,
                'x' => .x,
                'o' => .o,
                else => unreachable,
            };
        }
    }

    return .{
        .grid = grid,
        .size = size,
    };
}

pub fn jsonStringify(self: Board, out_writer: anytype) error{OutOfMemory}!void {
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
                .empty => _ = hack.appendAssumeCapacity('-'), // not nice either
                .x => _ = hack.appendAssumeCapacity('x'),
                .o => _ = hack.appendAssumeCapacity('o'),
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
                .empty => _ = try out_writer.writeByte('-'),
                .x => _ = try out_writer.writeByte('x'),
                .o => _ = try out_writer.writeByte('o'),
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
                .empty => print("-", .{}),
                .x => print("x", .{}),
                .o => print("o", .{}),
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
        [_]CellValue{ .empty, .empty, .empty },
        [_]CellValue{ .empty, .x, .o },
        [_]CellValue{ .empty, .empty, .empty },
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

    try testing.expectEqual(.empty, okGrid.grid[0][0]);
    try testing.expectEqual(.x, okGrid.grid[1][1]);
    try testing.expectEqual(.o, okGrid.grid[1][2]);

    // now check bad inputs
    try testing.expectError(error.NotPerfectSquare, parseFromSlice(testing.allocator, "-----"));
    try testing.expectError(error.InvalidCharacter, parseFromSlice(testing.allocator, "----zo---"));
}

test "jsonification" {
    const T = struct { board: Board };

    const staticVal = [3][3]CellValue{
        [_]CellValue{ .empty, .empty, .empty },
        [_]CellValue{ .empty, .x, .o },
        [_]CellValue{ .empty, .empty, .empty },
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
        [_]CellValue{ .empty, .empty, .empty },
        [_]CellValue{ .empty, .x, .o },
        [_]CellValue{ .empty, .empty, .empty },
    };
    var grid = makeTestBoardStatic(3, staticVal).withAllocator(testing.allocator);
    defer grid.deinit(testing.allocator);

    try testing.expectEqual(.empty, grid.grid[0][0]);
    try testing.expectEqual(.x, grid.grid[1][1]);
    try testing.expectEqual(.o, grid.grid[1][2]);
}
