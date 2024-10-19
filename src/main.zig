const std = @import("std");
const debug = std.debug;

const game = @import("game.zig");
const config = @import("config.zig");
const game_server = @import("game_server.zig");
const cli = @import("cli.zig");
const input = @import("input.zig");
const Ai = @import("ai.zig").Ai;
const Navigation = @import("input.zig").Navigation;

// this is main for cli only!
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cfg = try config.parseConfigFromArgs(allocator);

    cfg.debugPrint();

    // this main loop needs to create an appropriate server for the game
    var state = try game.State.init(allocator, game.GAME_SIZE);
    defer state.deinit(allocator);

    const ai = if (cfg.aiDifficulty != null) Ai.init(cfg.aiDifficulty.?) else null;

    const serv = game_server.UniversalServer.init(&state, ai, true);

    try cli.mainLoop(serv);
}
