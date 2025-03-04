// https://zig.news/yglcode/code-study-interface-idiomspatterns-in-zig-standard-libraries-4lkj
// Interface 5

const std = @import("std");

fn System(
    comptime Iface: type,
    comptime pushFn: *const fn (T: *Iface, data: u8) void,
) type {
    return struct {
        ptr: *Iface,

        const Self = @This();

        pub fn init(ptr: *Iface) Self {
            return .{
                .ptr = ptr,
            };
        }

        // wrap the original function
        fn push(self: *Self, value: u8) void {
            pushFn(self.ptr, value);
        }

        // use the wrapped function
        pub fn double(self: *Self, value: u7) void {
            const result: u8 = @as(u8, value) * 2;

            self.push(result);
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

    pub fn push(self: *@This(), ev: u8) void {
        self.values.append(ev) catch @panic("TestIntegration event overflow");
    }
};

test {
    var pusher = TestIntegration.init();
    var system = System(TestIntegration, TestIntegration.push).init(&pusher);

    system.double(127);
    try std.testing.expectEqual(pusher.values.buffer[0], 254);
}

// sidequest
test {
    const value: u7 = 127;
    const doubled: u8 = @as(u8, value) * 2;
    try std.testing.expectEqual(254, doubled);
}
