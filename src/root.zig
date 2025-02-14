const std = @import("std");
const testing = std.testing;

comptime {
    // _ = @import("main_app.zig");
    // _ = @import("main_server.zig");

    // add any non-imported things here

    _ = @import("Board.zig");
    // _ = @import("client.zig");
    _ = @import("game.zig");
    _ = @import("WinCondition.zig");

    // _ = @import("app/config.zig");
    // _ = @import("app/handler.zig");
    // _ = @import("app/input.zig");
    // _ = @import("app/renderer.zig");
}
