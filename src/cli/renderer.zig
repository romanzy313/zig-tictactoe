const std = @import("std");
const game = @import("common").game;

const ANSI_NORMAL: []const u8 = "\u{001b}[0m";
const ANSI_SELECTED: []const u8 = "\u{001b}[7m";
const CLEAR_TERM: []const u8 = "\x1b[2J\x1b[H";

pub fn render(writer: std.io.AnyWriter, state: game.ResolvedState, selection: game.CellPosition, err: ?anyerror) !void {
    try writer.writeAll(CLEAR_TERM);

    for (state.grid, 0..) |row, i| {
        for (row, 0..) |cell, j| {
            const ansiPrefix = if (selection.y == i and selection.x == j) ANSI_SELECTED else ANSI_NORMAL;
            switch (cell) {
                .Empty => try writer.print("{s}-{s}", .{ ansiPrefix, ANSI_NORMAL }),
                .X => try writer.print("{s}x{s}", .{ ansiPrefix, ANSI_NORMAL }),
                .O => try writer.print("{s}o{s}", .{ ansiPrefix, ANSI_NORMAL }),
            }
            try writer.writeAll(" ");
        }
        try writer.writeAll("\n");
    }

    // handle state accordingly.
    switch (state.status) {
        .TurnX => try writer.print("Player X turn\n", .{}),
        .TurnO => try writer.print("Player O turn\n", .{}),
        .WinX => try writer.print("Player X won\n", .{}),
        .WinO => try writer.print("Player O won\n", .{}),
        .Stalemate => try writer.print("Stalemate\n", .{}),
    }

    if (err == null) {
        try writer.print("\n", .{});
    } else {
        try writer.print("error: {any}\n", .{err});
    }
}

// TODO: test render()
