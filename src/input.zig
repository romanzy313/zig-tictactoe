const std = @import("std");
const testing = std.testing;

const game = @import("game.zig");

pub const Navigation = struct {
    pub const Direction = enum { Left, Down, Up, Right };

    gridSize: usize,
    pos: game.CellPosition,

    pub fn init(gridSize: usize, pos: game.CellPosition) Navigation {
        return .{
            .gridSize = gridSize,
            .pos = pos,
        };
    }

    pub fn onDir(self: *Navigation, dir: Direction) void {
        // var pos = self.pos.*;
        switch (dir) {
            .Left => {
                if (self.pos.x > 0) self.pos.x -= 1;
            },
            .Right => {
                if (self.pos.x < self.gridSize - 1) self.pos.x += 1;
            },
            .Up => {
                if (self.pos.y > 0) self.pos.y -= 1;
            },
            .Down => {
                if (self.pos.y < self.gridSize - 1) self.pos.y += 1;
            },
        }
    }
};

test Navigation {
    var nav = Navigation.init(3, .{ .x = 1, .y = 1 });

    nav.onDir(.Up);
    try testing.expectEqual(1, nav.pos.x);
    try testing.expectEqual(0, nav.pos.y);

    nav.onDir(.Up);
    // WARNING: this provides really bad feedback on error.
    try testing.expectEqual(game.CellPosition{ .x = 1, .y = 0 }, nav.pos);
}
