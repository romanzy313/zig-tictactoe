const std = @import("std");
const debug = std.debug;
const UUID = @import("uuid").UUID;

const game = @import("game.zig");
const Ai = @import("Ai.zig");
const GameState = @import("GameState.zig");
const Event = @import("events.zig").Event;

const handler = @import("cli/handler.zig");
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
            const raw = try input.RawMode.init(false);
            defer raw.deinit();

            const stdin = std.io.getStdIn().reader().any();
            const stdout = std.io.getStdOut().writer().any();

            var nav = input.Navigation.init(board_size);

            var game_handler = handler.GameHandler.init(stdout, &state);
            game_handler.cursor_pos = nav.pos;
            try game_handler.render(null); // render first frame

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
                        try game_handler.tick(.{ .hover = nav.pos });
                    },
                }
            }
        },
        .gui => {
            try runGui();
        },
    }
}

// maybe could be a good idea to use std.testing.refAllDeclsRecursive(@This())
// so that all files used here are tested?
// for now all tests are in root.zig
// comptime {
//     std.testing.refAllDeclsRecursive(@This());
// }
