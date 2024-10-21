const std = @import("std");
const testing = std.testing;

// pub const common = @import("common"); // test all common tests
// pub const client = @import("client");
// pub const server = @import("server");

// add files to be tested here...
// https://stackoverflow.com/questions/75762207/how-to-test-multiple-files-in-zig
comptime {
    // _ = @import("common/game.zig");

    // _ = @import("client/cli.zig");
    // _ = @import("client/input.zig");

    // _ = @import("server/game_repo.zig");
}

// test {
//     testing.refAllDecls(@This());
// }
