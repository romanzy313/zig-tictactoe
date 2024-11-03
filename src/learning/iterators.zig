const std = @import("std");

// how to do the iterators
// https://zig.guide/standard-library/iterators/

const ContainsIterator = struct {
    strings: []const []const u8,
    needle: []const u8,
    index: usize = 0,
    fn next(self: *ContainsIterator) ?[]const u8 {
        const index = self.index;
        for (self.strings[index..]) |string| {
            self.index += 1;
            if (std.mem.indexOf(u8, string, self.needle)) |_| {
                return string;
            }
        }
        return null;
    }
};

test "custom iterator" {
    var iter = ContainsIterator{
        .strings = &[_][]const u8{ "one", "two", "three" },
        .needle = "e",
    };

    try std.testing.expect(std.mem.eql(u8, iter.next().?, "one"));
    try std.testing.expect(std.mem.eql(u8, iter.next().?, "three"));
    try std.testing.expect(iter.next() == null);
}
