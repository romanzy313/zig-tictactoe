const std = @import("std");
pub const Ai = @import("Ai.zig");
pub const game = @import("game.zig");
pub const client = @import("client.zig");
pub const server = @import("server.zig");
pub const events = @import("events.zig");

test {
    std.testing.refAllDecls(@This());

    // for example this:
    // std.testing.refAllDeclsRecursive(@This());
    // will also test whatever these files import, and they import the vendor.
    // for now I am not testing the vendor as I am expecting it to work well.
}
