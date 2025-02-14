const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;

const EventEnvelope = struct {
    game_id: u32,
    tick: usize,
    event: Event,
};

const Event = struct { data: u8, done: bool };

pub const VTable = struct {
    publishEvent: *const fn (ctx: *anyopaque, event: Event) void,
};

const GameProjection = struct {
    ptr_publisher: *anyopaque,
    vtable: *const VTable,

    done: bool,
    values: ArrayList(u8),

    pub fn resolveFromEnvelope(self: *GameProjection, env: EventEnvelope) !void {
        self.resolveEvent(env.event);
    }

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

const SinglePublisher = struct {
    sent: std.BoundedArray(Event, 100),
    allocator: Allocator,

    pub fn init(allocator: Allocator) SinglePublisher {
        return SinglePublisher{
            .allocator = allocator,
            .sent = std.BoundedArray(Event, 100){},
        };
    }

    pub fn handler(
        self: *SinglePublisher,
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
        const self: *SinglePublisher = @ptrCast(@alignCast(ctx));

        // here I cant figure out who calls this
        // so i cant attach the id?

        self.sent.append(event) catch @panic("OOM"); // for now
    }
};

const testing = std.testing;

test SinglePublisher {
    var publisher = SinglePublisher.init(testing.allocator);
    var handler = try publisher.handler();
    defer handler.deinit();

    try handler.resolveEvent(.{ .data = 2, .done = false });

    try testing.expectEqual(0, publisher.sent.len);

    try handler.resolveEvent(.{ .data = 'a', .done = false });

    try testing.expectEqual(1, publisher.sent.len);
    try testing.expectEqual('b', publisher.sent.buffer[0].data);
}

// this is when issues arrise
const ScopedGame = struct {
    parent: *FullPublisher,
    game_id: u32,

    pub fn handler(
        self: *ScopedGame,
    ) !GameProjection {
        return try GameProjection.init(
            self.parent.allocator,
            self,
            &.{
                .publishEvent = ___publishEvent,
            },
        );
    }

    pub fn ___publishEvent(ctx: *anyopaque, event: Event) void {
        const self: *ScopedGame = @ptrCast(@alignCast(ctx));

        // here I cant figure out who calls this
        // so i cant attach the id?

        self.parent.sent.append(EventEnvelope{
            .game_id = self.game_id,
            .tick = 0,
            .event = event,
        }) catch @panic("OOM"); // for now

    }
};

// now I want a multi-publisher
// ability to route all needed events to their right place
// cant get it done
// what are my options?
// Segmentation fault at address 0x640
const FullPublisher = struct {
    sent: std.BoundedArray(EventEnvelope, 100),
    allocator: Allocator,
    instances: [2]?ScopedGame,

    pub fn init(allocator: Allocator) FullPublisher {
        return FullPublisher{
            .allocator = allocator,
            .instances = [_]?ScopedGame{null} ** 2,
            .sent = std.BoundedArray(EventEnvelope, 100){},
        };
    }

    pub fn handlerForGame(self: *FullPublisher, game_id: u32) !GameProjection {
        // this only works here and now
        // i cant be doing this

        self.instances[0] = ScopedGame{
            .parent = self,
            .game_id = game_id,
        };

        // also want to send it to it...

        return try self.instances[0].?.handler();
    }
};

test FullPublisher {
    var publisher = FullPublisher.init(testing.allocator);
    var handler = try publisher.handlerForGame(40);
    defer handler.deinit();

    try handler.resolveEvent(.{ .data = 2, .done = false });

    try testing.expectEqual(0, publisher.sent.len);

    try handler.resolveEvent(.{ .data = 'a', .done = false });

    try testing.expectEqual(1, publisher.sent.len);
    try testing.expectEqual(40, publisher.sent.buffer[0].game_id);
    try testing.expectEqual('b', publisher.sent.buffer[0].event.data);
}

const GameServer = struct {
    // it holds many games, one for now
    //
    allocator: Allocator,

    game_0: ?GameProjection,
    game_1: ?GameProjection,

    pub fn init(allocator: Allocator) GameServer {
        return GameServer{
            .allocator = allocator,
        };
    }

    pub fn newGame(self: *GameServer, id: u32) void {
        const inst = switch (id) {
            0 => self.game_0,
            1 => self.game_1,
        };
        _ = inst;
        // inst.* = GameProjection.init(allocator: Allocator, ptr_publisher: *anyopaque, vtable: *const VTable)
    }
};
