const std = @import("std");
const debug = std.debug;

const game = @import("game.zig");
const client = @import("client.zig");
const Ai = @import("Ai.zig");
const events = @import("events.zig");
const handler = @import("cli/handler.zig");

const config = @import("config.zig");
const input = @import("cli/input.zig");

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

// maybe could be a good idea to use std.testing.refAllDeclsRecursive(@This())
// so that all files used here are tested?
// for now all tests are in root.zig
// comptime {
//     std.testing.refAllDeclsRecursive(@This());
// }
