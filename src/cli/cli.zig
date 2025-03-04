const std = @import("std");
const input = @import("input.zig");
const GameState = @import("../GameState.zig");
const Renderer = @import("renderer.zig").Renderer;
const LocalGameHandler = @import("../LocalHandler.zig").LocalGameHandler;

pub fn runCli(state: *GameState) !void {
    const raw = try input.RawMode.init(false);
    defer raw.deinit();

    const stdin = std.io.getStdIn().reader().any();
    const stdout = std.io.getStdOut().writer().any();

    var nav = input.Navigation.init(state.board.size);

    var renderer = Renderer.init(stdout, nav.pos);

    var game_handler = LocalGameHandler(Renderer, Renderer.renderFn).init(&renderer, state);

    try game_handler.tick(.{ .rerender = {} });

    while (game_handler.is_playing) {
        const cmd = try input.readCommand(stdin);
        switch (cmd) {
            .Quit => {
                try stdout.print("Quitting...\n", .{});
                return;
            },
            .Select => {
                try game_handler.tick(.{ .select = nav.pos });
            },
            else => |nav_cmd| {
                switch (nav_cmd) {
                    .Left => nav.onDir(.Left),
                    .Right => nav.onDir(.Right),
                    .Up => nav.onDir(.Up),
                    .Down => nav.onDir(.Down),
                    else => unreachable,
                }
                // force update the local renderer
                // this is ugly but it works
                renderer.cursor_pos = nav.pos;

                try game_handler.tick(.{ .rerender = {} });
            },
        }
    }
}
