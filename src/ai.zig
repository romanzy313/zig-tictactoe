const std = @import("std");
const game = @import("game.zig");
pub const Difficulty = enum {
    Easy,
    Medium,
    Hard,
};
pub fn ComptimeAi(comptime diff: Difficulty) type {
    return switch (diff) {
        .Easy => struct {
            pub fn getMove(state: *game.State) game.CellPosition {
                return easyMove(state);
            }
        },
    };
}

pub const Ai = struct {
    difficulty: Difficulty,

    pub fn init(difficulty: Difficulty) Ai {
        return .{
            .difficulty = difficulty,
        };
    }
    pub fn getMove(self: @This(), state: *game.State) game.CellPosition {
        return switch (self.difficulty) {
            .Easy => easyMove(state),
            // else => error.AiDifficultyNotImplmeneted,
            else => @panic("not implmeneted"),
        };
    }
};

fn easyMove(state: *game.State) game.CellPosition {
    for (state.grid, 0..) |col, y| {
        for (col, 0..) |cell, x| {
            if (cell == .Empty) {
                return .{ .x = x, .y = y };
            }
        }
    }

    // is it okay to do this? or am I indroducing a potential DoS?
    // there must be a logic error for this to happen
    @panic("will never happen: ai is never evaluated on full board");
}
