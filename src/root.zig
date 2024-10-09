const std = @import("std");
const testing = std.testing;

// add files to be tested here...
// https://stackoverflow.com/questions/75762207/how-to-test-multiple-files-in-zig
comptime {
    _ = @import("board.zig");
    _ = @import("math.zig");
}
