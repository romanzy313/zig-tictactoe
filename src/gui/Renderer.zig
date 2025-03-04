const std = @import("std");
const rl = @import("raylib");
const AnyWriter = std.io.AnyWriter;

const game = @import("../game.zig");
const Board = @import("../Board.zig");
const GameState = @import("../GameState.zig");
const Event = @import("../events.zig").Event;
const LocalGameHandler = @import("../LocalHandler.zig").LocalGameHandler;

const cell_margin: f32 = 10;
const font_size: f32 = 160;

// confronts to comptime renderFn: *const fn (T: *Iface, state: GameState, maybe_err: ?Event.RuntimeError) void,

const Renderer = @This();

size: RenderSize,
cell_size: f32,
cell_count: usize,
cell_hovered: ?Board.CellPosition,

font: rl.Font,

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
        .cell_hovered = null,
        .font = rl.getFontDefault(),
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

pub fn renderFn(self: *Renderer, state: *GameState, maybe_err: ?Event.RuntimeError) !void {
    rl.beginDrawing();
    defer rl.endDrawing();

    rl.clearBackground(rl.Color.white);

    // draw the status bar
    rl.drawRectangleRec(.{
        .x = 0,
        .y = self.size.board_size,
        .width = self.size.board_size,
        .height = self.size.status_size,
    }, rl.Color.light_gray);

    for (state.board.grid, 0..) |row, i| {
        for (row, 0..) |cell, j| {
            // zig is an expressive langauge
            const hover = if (self.cell_hovered) |pos| if (pos.x == j and pos.y == i) true else false else false;
            // equivelent to:
            // const hover = if (self.cell_hovered) |pos|
            //     if (pos.x == j and pos.y == i) true else false
            // else
            //     false;

            self.drawCell(i, j, hover, cell);
        }
    }

    const status_font_size = 40;

    // const status_spacing = rl.measureTextEx(self.font, "Any text???", status_font_size, 1);

    const status: [*:0]const u8 = state.getStatusz();

    rl.drawTextEx(self.font, status, .{
        .x = 10,
        .y = self.size.board_size + 10,
    }, status_font_size, 1, rl.Color.black);

    if (maybe_err) |err| {
        rl.drawTextEx(self.font, err.toStringz(), .{
            .x = 10,
            .y = self.size.board_size + 50,
        }, status_font_size, 1, rl.Color.red);
    }
}

const GuiEvent = union(enum) {
    none: void,
    hover: Board.CellPosition,
    click: Board.CellPosition,
};

// this need to be ran once per frame
// and it needs to update the dir in here too..
pub fn getGuiEvent(self: *Renderer) GuiEvent {
    self.cell_hovered = null; // this is some nice spagetti, oh well

    const mouse_position = rl.getMousePosition();

    const board_size = self.size.board_size;

    if (mouse_position.x < 0 or mouse_position.x > board_size) {
        return GuiEvent{ .none = {} };
    }
    if (mouse_position.y < 0 or mouse_position.y > board_size) {
        return GuiEvent{ .none = {} };
    }

    const cell_count_f: f32 = @floatFromInt(self.cell_count);
    // the x and y must be flipped because my coordinates are different then raylibs
    const x_idx: usize = @intFromFloat(@floor((mouse_position.y / board_size) * cell_count_f));
    const y_idx: usize = @intFromFloat(@floor((mouse_position.x / board_size) * cell_count_f));

    self.cell_hovered = .{ .x = x_idx, .y = y_idx };

    // check for mouse input
    const is_click = rl.isMouseButtonPressed(.mouse_button_left);

    if (is_click) {
        return GuiEvent{ .click = .{ .x = x_idx, .y = y_idx } };
    }

    return GuiEvent{ .hover = self.cell_hovered.? };
}

// i need to get mouse position
// check if it collides with any cell
// check if mouse down is being pressed
// if yes, I need to return this information

fn drawCell(self: *Renderer, x_idx: usize, y_idx: usize, hover: bool, value: Board.CellValue) void {
    // calculate all margins
    //
    // const cell
    const x: f32 = @floatFromInt(x_idx);
    const y: f32 = @floatFromInt(y_idx);

    const x0 = x * self.cell_size + (x + 1) * cell_margin;
    const y0 = y * self.cell_size + (y + 1) * cell_margin;

    const cell_rec = rl.Rectangle.init(
        x0,
        y0,
        self.cell_size,
        self.cell_size,
    );

    // check if we hover

    // const is_hover = rl.checkCollisionPointRec(self.mouse_pos, cell_rec);

    const cell_color = if (hover) rl.Color.red else rl.Color.light_gray;

    // also draw an outline

    rl.drawRectangleRec(cell_rec, cell_color);

    rl.drawRectangleLinesEx(cell_rec, 2, rl.Color.black);

    const text: [*:0]const u8 = switch (value) {
        .empty => " ",
        .x => "x",
        .o => "o",
    };

    const text_size = rl.measureTextEx(self.font, text, font_size, 1);

    rl.drawTextEx(self.font, text, .{
        .x = x0 + self.cell_size / 2 - text_size.x / 2,
        .y = y0 + self.cell_size / 2 - text_size.y / 2,
    }, font_size, 1, rl.Color.black);
}
