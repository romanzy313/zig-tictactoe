const std = @import("std");
const game = @import("../game.zig");
const Board = @import("../Board.zig");

const ansi_normal: []const u8 = "\u{001b}[0m";
const ansi_selected: []const u8 = "\u{001b}[7m";
const clear_term: []const u8 = "\x1b[2J\x1b[H";

pub fn render(writer: std.io.AnyWriter, state: game.ResolvedState, selection: Board.CellPosition, err: ?anyerror) !void {
    try writer.writeAll(clear_term);

    for (state.board.grid, 0..) |row, i| {
        for (row, 0..) |cell, j| {
            const value: *const [1]u8 = switch (cell) {
                .empty => "-",
                .x => "x",
                .o => "o",
            };

            const is_selected = selection.y == i and selection.x == j;

            if (is_selected) {
                try writer.print("{s}{s}{s}", .{ ansi_selected, value, ansi_normal });
            } else {
                try writer.print("{s}", .{value});
            }

            try writer.writeAll(" ");
        }
        try writer.writeAll("\n");
    }

    // handle state accordingly.
    switch (state.status) {
        .turnX => try writer.print("Player X turn\n", .{}),
        .turnO => try writer.print("Player O turn\n", .{}),
        .winX => try writer.print("Player X won\n", .{}),
        .winO => try writer.print("Player O won\n", .{}),
        .stalemate => try writer.print("Stalemate\n", .{}),
    }

    if (err == null) {
        try writer.print("\n", .{});
    } else {
        try writer.print("error: {any}\n", .{err});
    }
}

// would be nice to include winning game render (like highlight the winning condition)
// i think its pretty important

// TODO: test render()
