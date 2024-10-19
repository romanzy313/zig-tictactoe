const std = @import("std");

const game = @import("game.zig");
const server = @import("server.zig");
const cli = @import("cli.zig");
const input = @import("input.zig");
const Ai = @import("ai.zig").Ai;
const Navigation = @import("input.zig").Navigation;

pub const GAME_SIZE = 3;
pub const STARTING_POSITION: game.CellPosition = .{ .x = 1, .y = 1 };

// this is main for cli only!
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var state = try game.State.init(allocator, GAME_SIZE);
    defer state.deinit(allocator);

    const raw = try cli.RawMode.init();
    defer raw.deinit();
    const stdin = std.io.getStdIn().reader().any();
    const stdout = std.io.getStdOut().writer().any();

    const ai = Ai.init(.Easy);

    const serv = server.LocalWithAi.init(&state, ai, true);

    var nav = Navigation.init(GAME_SIZE, STARTING_POSITION);
    try cli.render(stdout, &state, nav.pos, null);

    while (true) {
        const cmd = try cli.readCommand(stdin);

        switch (cmd) {
            .Quit => {
                try stdout.print("Quitting...\n", .{});
                return;
            },
            .Select => {
                const isPlaying = serv.submitMove(nav.pos) catch |e| {
                    try cli.render(stdout, &state, nav.pos, e);
                    continue;
                };

                if (!isPlaying) {
                    break;
                }
            },
            .Left => nav.onDir(.Left),
            .Right => nav.onDir(.Right),
            .Up => nav.onDir(.Up),
            .Down => nav.onDir(.Down),
        }
        try cli.render(stdout, &state, nav.pos, null);
    }

    try cli.render(stdout, &state, nav.pos, null);
    try stdout.print("Game over. Status: {any}\n", .{state.status});
}
