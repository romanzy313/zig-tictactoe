const std = @import("std");
const testing = std.testing;

comptime {
    // _ = @import("main_app.zig");
    // _ = @import("main_server.zig");

    // add any non-imported things here

    _ = @import("config.zig");
    _ = @import("Board.zig");
    _ = @import("client.zig");
    _ = @import("game.zig");
    _ = @import("WinCondition.zig");

    _ = @import("cli/handler.zig");
    _ = @import("cli/input.zig");
    _ = @import("cli/renderer.zig");
}
