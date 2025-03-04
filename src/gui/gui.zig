const std = @import("std");
const rl = @import("raylib");

const GameState = @import("../GameState.zig");
const LocalGameHandler = @import("../LocalHandler.zig").LocalGameHandler;
const Renderer = @import("Renderer.zig");

// run with
// zig build app -- local --gui
pub fn runGui(state: *GameState) anyerror!void {
    const initial_size = Renderer.RenderSize{
        .board_size = 600,
        .status_size = 100,
    };
    var renderer = Renderer.init(initial_size, state.board.size);
    defer renderer.deinit();
    var game_handler = LocalGameHandler(Renderer, Renderer.renderFn).init(&renderer, state);

    // once trigger the rendering
    //
    try game_handler.render(null);
    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key

        // update mouse navigation?
        renderer.updateMousePosition(rl.getMousePosition());

        // also ticks should be set to the game_handler
        // but actual intersection logic is done in the renderer...

        // this MUST be present here,
        // or else the render just gets stuck infinitely looping and closing the window becomes impossible
        try game_handler.tick(.{ .hover = .{ .x = 1, .y = 1 } });

        //----------------------------------------------------------------------------------
    }

    std.debug.print("GUI game endeded", .{});
}
