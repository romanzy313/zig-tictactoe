const std = @import("std");

const game = @import("game.zig");
const server = @import("server.zig");
const cli = @import("cli.zig");
const input = @import("input.zig");
const Ai = @import("ai.zig").Ai;
const Navigation = @import("input.zig").Navigation;

// this is main for cli only!
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // this main loop needs to create an appropriate server for the game
    var state = try game.State.init(allocator, game.GAME_SIZE);
    defer state.deinit(allocator);

    // const ai = Ai.init(.Easy);
    const ai = null;

    const serv = server.UniversalServer.init(&state, ai, true);

    try cli.mainLoop(serv);
}
