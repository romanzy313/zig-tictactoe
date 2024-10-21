const std = @import("std");

pub const uuid = @import("uuid/uuid.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
    // or
    // std.testing.refAllDeclsRecursive(@import("uuid/"))
}
