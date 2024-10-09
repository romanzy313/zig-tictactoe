const std = @import("std");

// why are these not in std?
// something like std.math.min(0, std.math.max(2, x + 1)); would be ncie

pub fn max(comptime T: type, a: T, b: T) T {
    if (a > b) {
        return a;
    }

    return b;
}
pub fn min(comptime T: type, a: T, b: T) T {
    if (a < b) {
        return a;
    }
    return b;
}
pub fn clamp(comptime T: type, val: T, minVal: T, maxVal: T) T {
    return max(T, min(T, val, maxVal), minVal);
}

test "clamp it" {
    try std.testing.expect(clamp(usize, 5, 0, 2) == @as(usize, 2));
    try std.testing.expect(clamp(i8, -1, 0, 2) == 0);
}
