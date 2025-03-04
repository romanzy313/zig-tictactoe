const std = @import("std");
const AnyWriter = std.io.AnyWriter;
const AnyReader = std.io.AnyReader;

const game = @import("../game.zig");
const Board = @import("../Board.zig");
const GameState = @import("../GameState.zig");
const Event = @import("../events.zig").Event;

const ansi_normal: []const u8 = "\u{001b}[0m";
const ansi_selected: []const u8 = "\u{001b}[7m";
const clear_term: []const u8 = "\x1b[2J\x1b[H";

const do_clear_term = true;

// confronts to comptime renderFn: *const fn (T: *Iface, state: GameState, cursor_pos: Board.CellPosition, maybe_err: ?Event.RuntimeError) void,
pub const Renderer = struct {
    writer: AnyWriter,

    pub fn init(writer: AnyWriter) Renderer {
        return .{
            .writer = writer,
        };
    }

    pub fn renderFn(self: *Renderer, state: *GameState, cursor_pos: Board.CellPosition, maybe_err: ?Event.RuntimeError) !void {
        if (do_clear_term) {
            try self.writer.writeAll(clear_term);
        }
        for (state.board.grid, 0..) |row, i| {
            for (row, 0..) |cell, j| {
                const value: *const [1]u8 = switch (cell) {
                    .empty => "-",
                    .x => "x",
                    .o => "o",
                };

                const is_selected = cursor_pos.y == i and cursor_pos.x == j;

                if (is_selected) {
                    try self.writer.print("{s}{s}{s}", .{ ansi_selected, value, ansi_normal });
                } else {
                    try self.writer.print("{s}", .{value});
                }

                try self.writer.writeAll(" ");
            }
            try self.writer.writeAll("\n");
        }

        try state.writeStatus(self.writer);
        try self.writer.print("\n", .{});

        if (maybe_err) |err| {
            try self.writer.print("\nerror: {any}", .{err});
        } else {
            try self.writer.print("\n", .{});
        }
    }
};
