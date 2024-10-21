const std = @import("std");
const debug = std.debug;

const game = @import("common").game;
const server = @import("common").server;
const Ai = @import("common").ai.Ai;

const config = @import("config.zig");
const cli = @import("cli.zig");
const input = @import("input.zig");
const Navigation = input.Navigation;

// this is main for cli only!
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cfg = try config.parseConfigFromArgs(allocator);

    cfg.debugPrint(); // will be cleared when game is ran!

    // this main loop needs to create an appropriate server for the game
    var state = try game.State.init(allocator, game.GAME_SIZE);
    defer state.deinit(allocator);

    const ai = if (cfg.aiDifficulty != null) Ai.init(cfg.aiDifficulty.?) else null;

    const serv = server.UniversalServer.init(&state, ai, true);

    try cli.mainLoop(serv);
}

// tests to evaluate are defined here.
// hardcoded, as std.testing.refAllDeclsRecursive(@This()); will try to test "@import("common").ai.Ai"
test {
    _ = @import("input.zig");
}
