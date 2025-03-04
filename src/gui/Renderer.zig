const std = @import("std");
const rl = @import("raylib");

const game = @import("../game.zig");
const Board = @import("../Board.zig");
const GameState = @import("../GameState.zig");
const Event = @import("../events.zig").Event;

const cell_margin: f32 = 10;

// confronts to comptime renderFn: *const fn (T: *Iface, state: GameState, cursor_pos: Board.CellPosition, maybe_err: ?Event.RuntimeError) void,

const Renderer = @This();

size: RenderSize,
cell_size: f32,
cell_count: usize,
mouse_pos: rl.Vector2,

pub const RenderSize = struct {
    board_size: f32,
    status_size: f32,
};

pub fn init(size: RenderSize, cell_count: usize) Renderer {
    rl.initWindow(
        @intFromFloat(size.board_size),
        @intFromFloat(size.board_size + size.status_size),
        "zig-tictactoe",
    );
    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // ugly but it works
    var self = Renderer{
        .size = size,
        .cell_size = 0,
        .cell_count = cell_count,
        .mouse_pos = .{ .x = -20, .y = -20 },
    };
    self.updateRenderSize(size, cell_count);

    return self;
}
pub fn deinit(self: *Renderer) void {
    _ = self;
    rl.closeWindow(); // Close window and OpenGL context
}

pub fn updateRenderSize(self: *Renderer, size: RenderSize, cell_count: usize) void {
    self.size = size;
    self.cell_count = cell_count;

    const cell_count_f: f32 = @floatFromInt(cell_count);

    self.cell_size = (size.board_size - (cell_margin * (cell_count_f + 1))) / cell_count_f;
}

pub fn updateMousePosition(self: *Renderer, pos: rl.Vector2) void {
    self.mouse_pos = pos;
}

pub fn renderFn(self: *Renderer, state: *GameState, cursor_pos: Board.CellPosition, maybe_err: ?Event.RuntimeError) !void {
    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(rl.Color.white);

    rl.drawRectangleRec(.{
        .x = 0,
        .y = self.size.board_size,
        .width = self.size.board_size,
        .height = self.size.status_size,
    }, rl.Color.blue);

    for (state.board.grid, 0..) |row, i| {
        for (row, 0..) |cell, j| {
            self.drawCell(i, j, cell);

            _ = cursor_pos;
            _ = maybe_err;
        }
    }

    // if (maybe_err) |err| {
    //     try self.writer.print("\nerror: {any}", .{err});
    // } else {
    //     try self.writer.print("\n", .{});
    // }
}

fn drawCell(self: *Renderer, x_idx: usize, y_idx: usize, value: Board.CellValue) void {
    // calculate all margins
    //
    // const cell
    const x: f32 = @floatFromInt(x_idx);
    const y: f32 = @floatFromInt(y_idx);
    const cell_rec = rl.Rectangle.init(
        x * self.cell_size + (x + 1) * cell_margin,
        y * self.cell_size + (y + 1) * cell_margin,
        self.cell_size,
        self.cell_size,
    );

    // check if we hover

    const is_hover = rl.checkCollisionPointRec(self.mouse_pos, cell_rec);

    const cell_color = if (is_hover) rl.Color.red else rl.Color.light_gray;

    rl.drawRectangleRec(cell_rec, cell_color);

    const text: *const [1]u8 = switch (value) {
        .empty => "",
        .x => "x",
        .o => "o",
    };
    _ = text;
}
