// https://zig.news/yglcode/code-study-interface-idiomspatterns-in-zig-standard-libraries-4lkj
// Interface 5

const std = @import("std");

fn System(
    comptime Iface: type,
    comptime pushSmth: *const fn (T: *Iface, data: u8) void,
) type {
    return struct {
        ptr: *Iface,

        const Self = @This();

        pub fn init(ptr: *Iface) Self {
            return .{
                .ptr = ptr,
            };
        }

        pub fn double(self: *Self, value: u7) void {
            const result: u8 = @as(u8, value) * 2;

            pushSmth(self.ptr, result);
        }
    };
}

fn TestInter(comptime T: type, comptime buffer_capacity: usize) type {
    return struct {
        values: std.BoundedArray(T, buffer_capacity),

        pub fn init() @This() {
            return .{
                .values = std.BoundedArray(T, buffer_capacity){},
            };
        }

        pub fn pushSmth(self: *@This(), ev: u8) void {
            self.values.append(ev) catch @panic("TestIntegration event overflow");
        }
    };
}

const TestIntegration = struct {
    values: std.BoundedArray(u8, 10),

    pub fn init() TestIntegration {
        return .{
            .values = std.BoundedArray(u8, 10){},
        };
    }

    pub fn pushSmth(self: *@This(), ev: u8) void {
        self.values.append(ev) catch @panic("TestIntegration event overflow");
    }
};

test {
    var pusher = TestIntegration.init();
    var system = System(TestIntegration, TestIntegration.pushSmth).init(&pusher);

    system.double(127);
    try std.testing.expectEqual(pusher.values.buffer[0], 254);
}

// sidequest
test {
    const value: u7 = 127;
    const doubled: u8 = @as(u8, value) * 2;
    try std.testing.expectEqual(254, doubled);
}
