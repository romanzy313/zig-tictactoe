const std = @import("std");

const Inner = struct {
    rows: []u8,

    pub fn mutate(self: @This(), v: u8) void {
        self.rows[0] = v;
    }
};

const Outer = struct {
    inner: *Inner,

    pub fn print(self: @This()) void {
        for (self.inner.rows) |i| {
            std.debug.print("{}\n", .{i});
        }
    }

    pub fn increaseAll(self: @This()) void {
        // * is automatically put here like so: self.inner.*.rows
        for (self.inner.rows, 0..) |v, i| {
            self.inner.rows[i] = v + 1;
        }
    }
};

fn mutateOuter(outer: Outer, v: u8) void {
    outer.inner.mutate(v);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const rows = try allocator.dupe(u8, &.{ 1, 2, 3 }); // shorthand easy slice creation. Dupe == copy.
    defer allocator.free(rows);

    // or manually allocate and do a for loop
    // const rows = try allocator.alloc(u8, 3);

    var inner = Inner{ .rows = rows };

    const outer = Outer{ .inner = &inner }; // pass a pointer

    outer.print();
}

const testing_allocator = std.testing.allocator;

test "tests" {

    // This allocates a "slice" and fulls it up with values
    // the size needs to be known at compiletime, hense the
    // second param is []const T. In runtime need to alocate explicitly.
    const rows = try testing_allocator.dupe(u8, &.{ 1, 2, 3 });
    defer testing_allocator.free(rows);

    // this does not work, as compiler resolves it at comptime and the type becomes *const [3]u8
    // creating of []u8 without allocator is impossible, as zig has no hidden control flow!
    // const rows = ([_]u8{ 0, 2, 3 })[0..];

    var inner = Inner{ .rows = rows };

    const outer = Outer{ .inner = &inner };

    // std.testing.expectEqual(.{ 1, 2, 3 }, outer.inner.rows);

    outer.inner.mutate(0);

    try std.testing.expectEqual(0, outer.inner.rows[0]);

    const result = [_]u8{ 0, 2, 3 };
    const casted = result[0..];
    // how can i compare teh full value without allocation?
    // yes I can check all individually, but this is getting silly.
    try std.testing.expectEqualSlices(u8, casted, outer.inner.rows);

    // can inline, but wierly
    try std.testing.expectEqualSlices(u8, ([_]u8{ 0, 2, 3 })[0..], outer.inner.rows);

    mutateOuter(outer, 2);

    try std.testing.expectEqualSlices(u8, ([_]u8{ 2, 2, 3 })[0..], outer.inner.rows);

    outer.increaseAll();

    try std.testing.expectEqualSlices(u8, ([_]u8{ 3, 3, 4 })[0..], outer.inner.rows);
}
