const std = @import("std");
const debug = std.debug;
const UUID = @import("uuid").UUID;

const game = @import("game.zig");
const Ai = @import("Ai.zig");
const GameState = @import("GameState.zig");
const Event = @import("events.zig").Event;

const handler = @import("app/handler.zig");
const config = @import("app/config.zig");
const input = @import("app/input.zig");

// this is main for cli only!
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse arguments here
    const board_size = 3;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // const cfg = try config.parseConfig(allocator, args[1..]);

    // std.debug.print("config is {any}\n", .{cfg});
    // std.process.exit(0);

    // cfg.debugPrint(); // will be cleared when game is ran!

    const raw = try input.RawMode.init(false);
    defer raw.deinit();

    const stdin = std.io.getStdIn().reader().any();
    const stdout = std.io.getStdOut().writer().any();

    var state = try GameState.init(allocator, &[_]Event{
        .{ .gameCreated = .{ .gameId = UUID.init(), .boardSize = board_size } },
        .{ .playerJoined = .{ .playerId = .{ .human = UUID.initFromNumber(1) }, .side = .x } },
        .{ .playerJoined = .{ .playerId = .{ .human = UUID.initFromNumber(2) }, .side = .o } },
    });
    defer state.deinit();
    // create handler and client
    // classic dilemma: client needs handler and handler need client...
    var game_handler = handler.GameHandler.init(stdin, stdout, &state);

    try game_handler.run();
}

// maybe could be a good idea to use std.testing.refAllDeclsRecursive(@This())
// so that all files used here are tested?
// for now all tests are in root.zig
// comptime {
//     std.testing.refAllDeclsRecursive(@This());
// }
