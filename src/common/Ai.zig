const std = @import("std");
const game = @import("game.zig");
const Board = @import("Board.zig");

pub const Difficulty = enum {
    easy,
    medium,
    hard,
};

pub fn getMove(difficulty: Difficulty, state: *game.ResolvedState) !Board.CellPosition {
    return switch (difficulty) {
        .easy => easyMove(state),
        // else => error.AiDifficultyNotImplmeneted,
        else => @panic("not implmeneted"),
    };
}

fn easyMove(state: *game.ResolvedState) !Board.CellPosition {
    // TODO: try an iterator?
    for (state.board.grid, 0..) |col, y| {
        for (col, 0..) |cell, x| {
            if (cell == .Empty) {
                return .{ .x = x, .y = y };
            }
        }
    }

    // is it okay to do this? or am I indroducing a potential DoS?
    // there must be a logic error for this to happen
    return error.NoAvailableMoves;
}
