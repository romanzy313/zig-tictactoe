const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
// partially from
// https://zig.news/yglcode/code-study-interface-idiomspatterns-in-zig-standard-libraries-4lkj
// this passes the implementation in
const MainImpl = struct {
    pub const VTable = struct {
        say: *const fn (ctx: *anyopaque, msg: []const u8) anyerror!void,
    };

    ptr: *anyopaque,
    vtable: *const VTable,
    allocator: std.mem.Allocator,

    pub fn sayLouder(self: MainImpl, msg: []const u8) !void {
        const upper = try sayLouderFn(self.allocator, msg);
        defer self.allocator.free(upper);

        try self.vtable.say(self.ptr, upper);
    }

    pub fn init(allocator: Allocator, obj: anytype) MainImpl {
        const Ptr = @TypeOf(obj);
        // how do I check for non-const?
        // std.debug.print("{any}", @typeInfo(Ptr));
        assert(@typeInfo(Ptr) == .Pointer); // Must be a pointer
        assert(@typeInfo(Ptr).Pointer.size == .One); // Must be a single-item pointer
        assert(@typeInfo(@typeInfo(Ptr).Pointer.child) == .Struct); // Must point to a struct
        const impl = struct {
            fn say(ptr: *anyopaque, msg: []const u8) !void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                try self.say(msg);
            }
        };

        return .{
            .ptr = obj,
            .vtable = &.{
                .say = impl.say,
            },
            .allocator = allocator,
        };
    }
};

const Variant1 = struct {
    writer: std.io.AnyWriter,

    pub fn init(writer: std.io.AnyWriter) Variant1 {
        return .{
            .writer = writer,
        };
    }

    fn say(self: Variant1, msg: []const u8) !void {
        try self.writer.writeAll(msg);
        try self.writer.writeAll("\n");
    }
};

test "vtable" {
    const allocator = std.testing.allocator;

    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    const writer = list.writer().any();

    // const obj = Variant1.init(writer); // this gives error error: expected type '*anyopaque', found '*const vtable_from_inside.Variant1'
    var obj = Variant1.init(writer); // but this is fine...

    var impl = MainImpl.init(allocator, &obj);

    try impl.sayLouder(@as([]const u8, "Hello VTable"));

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

    return result;
}

test sayLouderFn {
    const allocator = std.testing.allocator;
    const res = try sayLouderFn(allocator, @as([]const u8, "Hello"));
    defer allocator.free(res); // dont forget to free...

    try std.testing.expectEqualSlices(u8, @as([]const u8, "HELLO!!!"), res);
    try std.testing.expect(std.mem.eql(u8, res, "HELLO!!!")); // or can check it "raw"
}
