const std = @import("std");

// inspired from here https://github.com/ziglang/zig/issues/20663
// and here https://github.com/kooparse/zalgebra/blob/1ab7f25cd3f947289e98a617ae785607bbc5054e/src/generic_vector.zig#L46-L51
// but this is not working actually!

const Storage1 = struct {
    pub fn init() Storage1 {
        return .{};
    }
    pub fn append(self: Storage1, anything: u42) void {
        _ = self;

        std.debug.print("STORAGE 1: {d}\n", .{anything});
    }
};
const Storage2 = struct {
    extra: u40,
    pub fn init(extra: u40) Storage2 {
        return .{
            .extra = extra,
        };
    }

    pub fn append(self: Storage2, anything: u42) void {
        std.debug.print("STORAGE 2 way of writing things is '{d}'\n", .{anything + self.extra});
    }
};

const Variant = enum { one, two };

pub fn AnyStorage(comptime variant: Variant) type {
    return struct {
        const Self = @This();

        const init = switch (variant) {
            .one => Storage1.init,
            .two => Storage2.init,
        };

        pub usingnamespace switch (variant) {
            .one => struct {
                pub fn append(self: Storage1, anything: u42) void {
                    self.append(anything);
                }
            },
            .two => struct {
                pub fn append(self: Storage2, anything: u42) void {
                    self.append(anything);
                }
            },
        };
        // pub usingnamespace T;

        // pub fn append(self: Self, anything: u42) void {
        //     T.append(self, anything);
        // }

        pub fn appendTwo(self: Self, anything1: u42, anything2: u42) void {
            self.append(self, anything1);
            self.append(self, anything2);
        }
    };
}

test AnyStorage {
    const one = AnyStorage(.one).init();
    one.append(10);

    const two = AnyStorage(.two).init(123);
    two.append(10);

    const two2 = AnyStorage(.two).init(123);
    two2.appendTwo(12, 34);

    // any_storage.append(self: Storage1, anything: u42)
}

/// Mixin to provide methods to manipulate the `_counter` field.
pub fn CounterMixin(comptime T: type) type {
    return struct {
        pub fn increment(m: *@This()) void {
            const x: *T = @alignCast(@fieldParentPtr("counter", m));
            x._counter += 1;
        }
        pub fn reset(m: *@This()) void {
            const x: *T = @alignCast(@fieldParentPtr("counter", m));
            x._counter = 0;
        }
    };
}

pub const Foo = struct {
    _counter: u32 = 0,
    counter: CounterMixin(Foo) = .{},
};
