const std = @import("std");
const game = @import("game.zig");
const Board = @import("Board.zig");

pub const Difficulty = enum {
    easy,
    medium,
    hard,

    pub fn fromString(val: []u8) !Difficulty {
        inline for (@typeInfo(Difficulty).Enum.fields) |f| {
            // std.debug.print("{d} {s}\n", .{ f.value, f.name });
            if (std.mem.eql(u8, f.name, val)) {
                return @enumFromInt(f.value);
            }
        }
        return error.InvalidDifficulty;
    }
};

pub fn getMove(difficulty: Difficulty, board: Board) !Board.CellPosition {
    return switch (difficulty) {
        .easy => easyMove(board),
        // else => error.AiDifficultyNotImplmeneted,
        else => return error.AiDifficultyNotimplemented,
    };
}

fn easyMove(board: Board) !Board.CellPosition {
    // TODO: try an iterator?
    for (board.grid, 0..) |col, y| {
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

// this is an Ai which will win or draw a game
// like described here https://en.wikipedia.org/wiki/Tic-tac-toe#Strategy
// fn hardMove(state: *game.ResolveState) !Board.CellPosition {
//     // if its first move, always go to the center.
// }
