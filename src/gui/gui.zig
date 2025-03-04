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

    renderer.updateMousePosition(rl.getMousePosition());
    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key

        const gui_evt = renderer.getGuiEvent();

        switch (gui_evt) {
            .click => |ev| try game_handler.tick(.{ .select = .{ .x = ev.x, .y = ev.y } }),
            .hover => {
                // this still need to keep the rendering though
                try game_handler.tick(.{ .rerender = {} });
            },
            .none => {
                // nothing really.
                try game_handler.tick(.{ .rerender = {} });
            },
        }
        // update mouse state here
        // renderer.updateMousePosition(rl.getMousePosition());

        // i need to get the actions from the game to here
        // and apply them on game_handler
        // try game_handler.tick(.{ .select = .{ .x = 1, .y = 1 } });

        // also ticks should be set to the game_handler
        // but actual intersection logic is done in the renderer...

        // force rerender every frame, not needed?
        // try game_handler.tick(.{ .rerender = {} });
        //----------------------------------------------------------------------------------
    }

    std.debug.print("GUI game endeded", .{});
}
