const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;

const Event = struct { data: u8, done: bool };

pub const VTable = struct {
    publishEvent: *const fn (ctx: *anyopaque, event: Event) void,
};

const GameProjection = struct {
    ptr_publisher: *anyopaque,
    vtable: *const VTable,

    done: bool,
    values: ArrayList(u8),

    pub fn resolveEvent(self: *GameProjection, ev: Event) !void {
        // game logic
        try self.values.append(ev.data);
        if (self.values.items.len == 5) {
            // update local copy
            self.done = true;
            // send the event
            self.vtable.publishEvent(self.ptr_publisher, .{ .data = 0, .done = true });
        } else if (ev.done) {
            self.done = true;
        } else if (ev.data == 'a') {
            self.vtable.publishEvent(self.ptr_publisher, .{ .data = 'b', .done = true });
        }
    }

    pub fn init(
        allocator: Allocator,
        ptr_publisher: *anyopaque,
        vtable: *const VTable,
    ) !GameProjection {
        // hmmm, how to do this... As I do want there to be a sane initialization

        // actually init thing here

        return GameProjection{
            .ptr_publisher = ptr_publisher,
            .vtable = vtable,
            .done = false,
            .values = ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *GameProjection) void {
        self.values.deinit();
    }
};

// all things go though the publisher

const MemPublisher = struct {
    sent: std.BoundedArray(Event, 100),
    allocator: Allocator,

    pub fn init(allocator: Allocator) MemPublisher {
        return MemPublisher{
            .allocator = allocator,
            .sent = std.BoundedArray(Event, 100){},
        };
    }

    pub fn handler(
        self: *MemPublisher,
    ) !GameProjection {
        return try GameProjection.init(
            self.allocator,
            self,
            &.{
                .publishEvent = ___publishEvent,
            },
        );
    }

    /// this is really an interal function for the GameProjection to use
    /// must never be called directly!
    pub fn ___publishEvent(ctx: *anyopaque, event: Event) void {
        const self: *MemPublisher = @ptrCast(@alignCast(ctx));
        self.sent.append(event) catch @panic("OOM"); // for now
    }
};

const testing = std.testing;

test "rough" {
    var publisher = MemPublisher.init(testing.allocator);
    var handler = try publisher.handler();
    defer handler.deinit();

    try handler.resolveEvent(.{ .data = 2, .done = false });

    try testing.expectEqual(0, publisher.sent.len);

    try handler.resolveEvent(.{ .data = 'a', .done = false });

    try testing.expectEqual(1, publisher.sent.len);
    try testing.expectEqual('b', publisher.sent.buffer[0].data);
}

// now I want a multi-publisher
// ability to route all needed events to their right place
