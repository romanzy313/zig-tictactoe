const std = @import("std");
const debug = std.debug;
const UUID = @import("uuid").UUID;

const game = @import("game.zig");
const Ai = @import("Ai.zig");
const GameState = @import("GameState.zig");
const Event = @import("events.zig").Event;
const runCli = @import("cli/cli.zig").runCli;

const parseConfig = @import("config.zig").parseConfig;
const input = @import("cli/input.zig");
const runGui = @import("gui/gui.zig").runGui;

// this is main for cli only!
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse arguments here
    const board_size = 3;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const config = try parseConfig(allocator, args[1..]);

    const renderMode = config.renderMode();

    var state = try GameState.init(allocator, &[_]Event{
        .{ .gameCreated = .{ .gameId = UUID.init(), .boardSize = board_size } },
        .{ .playerJoined = .{ .playerId = .{ .human = UUID.initFromNumber(1) }, .side = .x } },
        .{ .playerJoined = .{ .playerId = .{ .human = UUID.initFromNumber(2) }, .side = .o } },
    });
    defer state.deinit();

    switch (renderMode) {
        .cli => {
            try runCli(&state);
        },
        .gui => {
            try runGui(&state);
        },
    }
}

// maybe could be a good idea to use std.testing.refAllDeclsRecursive(@This())
// so that all files used here are tested?
// for now all tests are in root.zig
// comptime {
//     std.testing.refAllDeclsRecursive(@This());
// }
