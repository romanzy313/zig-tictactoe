const std = @import("std");
const debug = std.debug;

const game = @import("common").game;
const client = @import("common").client;
const Ai = @import("common").Ai;
const events = @import("common").events;
const handler = @import("handler.zig");

const config = @import("config.zig");
const input = @import("input.zig");

// this is main for cli only!
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse arguments here
    const board_size = 5;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const cfg = try config.parseConfig(allocator, args[1..]);

    std.debug.print("config is {any}\n", .{cfg});
    // std.process.exit(0);

    // cfg.debugPrint(); // will be cleared when game is ran!

    const raw = try input.RawMode.init(false);
    defer raw.deinit();

    const stdin = std.io.getStdIn().reader().any();
    const stdout = std.io.getStdOut().writer().any();

    // create handler and client
    // classic dilemma: client needs handler and handler need client...
    var game_handler = handler.GameHandler.init(stdin, stdout, board_size);
    var game_client = client.Client{
        .local = try client.LocalClient.init(
            allocator,
            .{
                //.withAi = .{ .aiDifficulty = .easy, .boardSize = board_size, .playerSide = .x },
                .multiplayer = .{ .boardSize = board_size, .playerSide = .x },
            },
            &game_handler,
        ),
    };
    defer game_client.deinit();

    game_handler.setClient(game_client);

    // input and navigation should be handled here.

    try game_handler.run();
}

// tests to evaluate are defined here.
// hardcoded, as std.testing.refAllDeclsRecursive(@This()); will try to test "@import("common").ai.Ai"
test {
    _ = @import("config.zig");
    _ = @import("handler.zig");
    _ = @import("input.zig");
    _ = @import("renderer.zig");
}
