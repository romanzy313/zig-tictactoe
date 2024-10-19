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

    try cli.mainLoop(allocator);
}
