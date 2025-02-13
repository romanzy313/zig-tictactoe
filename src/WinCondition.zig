const std = @import("std");
const testing = std.testing;

const game = @import("game.zig");
const Board = @import("Board.zig");

// TODO:
// I would like to emit event called GameOver
// so that everyone knows whatsup
// this would really mean an event bus interface
// where events can emit events
// and important part is that this is enforced by the server
// in the case of offline play the server should be running locally

side: game.PlayerSide,
startsAt: Board.CellPosition,

// direction is tricky.
// horizontal always goes right
// vertical always goes down
// diagDown always goes right and down
// diagUp always does right and up
dir: enum { hor, vert, diagDown, diagUp },

const WinCondition = @This();

pub fn check(grid: [][]Board.CellValue) ?WinCondition {
    const size = grid.len;

    if (size == 3) {
        // TODO:
        // use optimized 3x3 algo
        // try to minmax this. maybe SIMD?
        return checkAnySize(grid, size);
    }

    return checkAnySize(grid, size);
}

fn checkAnySize(grid: [][]Board.CellValue, size: usize) ?WinCondition {
    const win_count: i8 = @intCast(size);
    const win_count_usize: usize = @intCast(win_count);

    //check horizontals
    for (0..size) |y| { // row
        var count: i8 = 0;

        for (0..size) |x| { // column
            const cell = grid[y][x];
            switch (cell) {
                .empty => {
                    count = 0;
                    continue;
                },
                .x => count += 1,
                .o => count -= 1,
            }

            // std.debug.print("HOR: we are going over x = {}, y = {}, count = {}\n", .{ x, y, count });

            if (count == win_count) return WinCondition{
                .side = .x,
                .dir = .hor,
                .startsAt = .{ .x = x + 1 - win_count_usize, .y = y },
            };
            if (count == -win_count) return WinCondition{
                .side = .o,
                .dir = .hor,
                .startsAt = .{ .x = x + 1 - win_count_usize, .y = y },
            };
        }
    }

    //check verticals
    for (0..size) |x| {
        var count: i8 = 0;

        for (0..size) |y| {
            const cell = grid[y][x];
            switch (cell) {
                .empty => {
                    count = 0;
                    continue;
                },
                .x => count += 1,
                .o => count -= 1,
            }
            // std.debug.print("VERT: we are going over x = {}, y = {}, count = {}\n", .{ x, y, count });

            if (count == win_count) return WinCondition{
                .side = .x,
                .dir = .vert,
                .startsAt = .{ .x = x, .y = y + 1 - win_count_usize },
            };
            if (count == -win_count) return WinCondition{
                .side = .o,
                .dir = .vert,
                .startsAt = .{ .x = x, .y = y + 1 - win_count_usize },
            };
        }
    }

    // TODO: add win_count here too

    // check diagonals
    for (0..(size - 2)) |dy| {
        for (0..(size - 2)) |dx| {
            // std.debug.print("DIAG: we are going over dx = {}, dy = {}\n", .{ dx, dy });

            // going down
            if (grid[dy][dx] != .empty and grid[dy][dx] == grid[dy + 1][dx + 1] and grid[dy + 1][dx + 1] == grid[dy + 2][dx + 2]) {
                const side: game.PlayerSide = switch (grid[dy][dx]) {
                    .x => .x,
                    .o => .o,
                    else => unreachable,
                };
                return WinCondition{ .side = side, .dir = .diagDown, .startsAt = .{ .x = dx, .y = dy } };
            }

            // going up
            if (grid[dy + 2][dx] != .empty and grid[dy + 2][dx] == grid[dy + 1][dx + 1] and grid[dy + 1][dx + 1] == grid[dy][dx + 2]) {
                const side: game.PlayerSide = switch (grid[dy + 2][dx]) {
                    .x => .x,
                    .o => .o,
                    else => unreachable,
                };
                return WinCondition{ .side = side, .dir = .diagUp, .startsAt = .{ .x = dx, .y = dy + 2 } };
            }
        }
    }

    return null;
}
/// checks if given cell participated in the win condition
/// usefull to render game over board
pub fn isInWinCond(self: WinCondition, pos: Board.CellPosition) bool {
    _ = self;
    _ = pos;
    return false;
}

test checkAnySize {
    var hor1 = try Board.parseFromSlice(testing.allocator, "---xxx---");
    defer hor1.deinit(testing.allocator);
    try testing.expectEqualDeep(WinCondition{
        .side = .x,
        .startsAt = .{ .x = 0, .y = 1 },
        .dir = .hor,
    }, checkAnySize(hor1.grid, @as(usize, 3)));

    var hor2 = try Board.parseFromSlice(testing.allocator, "-x--xxooo");
    defer hor2.deinit(testing.allocator);
    try testing.expectEqualDeep(WinCondition{
        .side = .o,
        .startsAt = .{ .x = 0, .y = 2 },
        .dir = .hor,
    }, checkAnySize(hor2.grid, @as(usize, 3)));

    var vert1 = try Board.parseFromSlice(testing.allocator, "-x--x--x-");
    defer vert1.deinit(testing.allocator);
    try testing.expectEqualDeep(WinCondition{
        .side = .x,
        .startsAt = .{ .x = 1, .y = 0 },
        .dir = .vert,
    }, checkAnySize(vert1.grid, @as(usize, 3)));

    var vert2 = try Board.parseFromSlice(testing.allocator, "-xo-xo--o");
    defer vert2.deinit(testing.allocator);
    try testing.expectEqualDeep(WinCondition{
        .side = .o,
        .startsAt = .{ .x = 2, .y = 0 },
        .dir = .vert,
    }, checkAnySize(vert2.grid, @as(usize, 3)));

    var diagDown = try Board.parseFromSlice(testing.allocator, "x---x---x");
    defer diagDown.deinit(testing.allocator);
    try testing.expectEqualDeep(WinCondition{
        .side = .x,
        .startsAt = .{ .x = 0, .y = 0 },
        .dir = .diagDown,
    }, checkAnySize(diagDown.grid, @as(usize, 3)));

    var diagUp = try Board.parseFromSlice(testing.allocator, "--o-o-o--");
    defer diagUp.deinit(testing.allocator);
    try testing.expectEqualDeep(WinCondition{
        .side = .o,
        .startsAt = .{ .x = 0, .y = 2 },
        .dir = .diagUp,
    }, checkAnySize(diagUp.grid, @as(usize, 3)));
}
