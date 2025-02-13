const std = @import("std");
const Allocator = std.mem.Allocator;

// partially from
// https://zig.news/yglcode/code-study-interface-idiomspatterns-in-zig-standard-libraries-4lkj
// this creates an interface from within the abstrctucted constructor
const Interface = struct {
    pub const VTable = struct {
        say: *const fn (ctx: *anyopaque, msg: []const u8) anyerror!void,
    };

    ptr: *anyopaque,
    vtable: *const VTable,
    allocator: std.mem.Allocator,

    pub fn sayLouder(self: Interface, msg: []const u8) !void {
        const upper = try sayLouderFn(self.allocator, msg);
        defer self.allocator.free(upper);

        try self.vtable.say(self.ptr, upper);
    }
};

const Implementation = struct {
    writer: std.io.AnyWriter,
    allocator: Allocator,

    pub fn init(allocator: Allocator, writer: std.io.AnyWriter) Implementation {
        return .{
            .writer = writer,
            .allocator = allocator,
        };
    }

    pub fn handler(self: *Implementation) Interface {
        return .{
            .ptr = self,
            .vtable = &.{
                .say = say,
            },
            .allocator = self.allocator,
        };
    }

    fn say(ctx: *anyopaque, msg: []const u8) !void {
        const self: *Implementation = @ptrCast(@alignCast(ctx));
        try self.writer.writeAll(msg);
        try self.writer.writeAll("\n");
    }
};

test "vtable" {
    const allocator = std.testing.allocator;

    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    const writer = list.writer().any();
    var impl = Implementation.init(allocator, writer);
    const handler = impl.handler();

    try handler.sayLouder(@as([]const u8, "Hello VTable"));

    try std.testing.expectEqualSlices(u8, "HELLO VTABLE!!!\n", list.items);
    try std.testing.expect(std.mem.eql(u8, list.items, "HELLO VTABLE!!!\n"));
}

pub fn sayLouderFn(allocator: Allocator, msg: []const u8) ![]const u8 {
    // this needs an allocation for every time...
    var result = try allocator.alloc(u8, msg.len + 3);

    for (msg, 0..) |char, i| {
        result[i] = std.ascii.toUpper(char);
    }
    @memcpy(result[msg.len .. msg.len + 3], "!!!");

    // or mutate directly:
    // result[msg.len] = '!';

    return result;
}

test sayLouderFn {
    const allocator = std.testing.allocator;
    const res = try sayLouderFn(allocator, @as([]const u8, "Hello"));
    defer allocator.free(res); // dont forget to free...

    try std.testing.expectEqualSlices(u8, @as([]const u8, "HELLO!!!"), res);
    try std.testing.expect(std.mem.eql(u8, res, "HELLO!!!")); // or can check it "raw"
}
