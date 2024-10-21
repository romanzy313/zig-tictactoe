const std = @import("std");
const testing = std.testing;

const SomeStruct = struct {
    raw: [8]u8,

    pub fn init(input: [8]u8) SomeStruct {
        return .{
            .raw = &input,
        };
    }

    pub fn toString(self: SomeStruct) []const u8 {
        var new: [10]u8 = undefined;
        const cpy = std.mem.copyForwards(u8, new[1..8], self.raw);

        cpy[0] = '!';
        cpy[9] = '?';
        return cpy;
    }
};

test "wierd bug" {
    const abcd = "12345678";
    const i = SomeStruct.init(@as([8]u8, abcd));

    const out = i.toString();

    try testing.expectEqual("!12345678!", out);
}
