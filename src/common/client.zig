const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const game = @import("game.zig");
const events = @import("events.zig");
const Ai = @import("Ai.zig");
const Board = @import("Board.zig");

/// this is a game client!
/// `LocalClient` emulates server with ai, even history is not stored for now
/// `RemoteClient` will use websockets and sync that way, but unsure how callback based rendering is done
pub const Client = union(enum) {
    // should the allocator be stored here?

    local: LocalClient,
    // remote: RemoteClient, // TODO: reintroduce

    // this does not work as intendet...
    pub fn deinit(self: *Client) void {
        switch (self.*) {
            inline else => |*case| return case.deinit(),
        }
        // switch (self.*) {
        //     .local => {
        //         self.local.deinit();
        //     },
        //     .remote => {
        //         self.remote.deinit();
        //     },
        // }
    }

    pub fn handleEvent(self: *Client, ev: events.Event) !void {
        switch (self.*) {
            inline else => |*case| return case.handleEvent(ev),
        }
    }

    pub fn state(self: *Client) game.ResolvedState {
        // we have to cast self to switch?
        switch (self.*) {
            inline else => |*case| return case.state,
            // inline else => |*case| return case.__getState(),
        }
        // return self.local.state;
    }
};
// const RenderFn = fn () void;
// pub const Renderer = struct {
//     count: usize = 0,
//     allocFn: fn (self: *Allocator, byte_count: usize, alignment: u29) anyerror![]u8,
//     pub fn onUpdate(self: *Renderer) void {
//         self.count += 1;
//     }
// };

// i guess I need to be an interface. I must provide pointer to self + a function to handle the updates
// i can do "vtable_from_inside" method. the oassed struct must implement .onStateChanged()
// these clients must save the pointer of a callback and its function, and pass the pointer in explicitly.
// additionally, errors must be sent somehow, and errors must be a []const u8? but then its allocator city
// const RenderFn = fn(err: anyerror) void; // errors can be sent too... I can send them separately though

// OR
// i could just pass the handler directly, as the game is meant to be ran on cli.
// What if gui is needed (even when I cant find a nice framework)? how to do the testing of this? or do full end-to-end testing

// hmmm, how to do onStateChange?
// pub OnStateChange1 = *const fn (*anyopaque, game.ResolvedState) void;

const VTable = struct {
    onStateChange: *const fn (ctx: *anyopaque, state: game.ResolvedState) void,
};

fn createVTable(obj: anytype) *const VTable {
    const Ptr = @TypeOf(obj);

    const vtable = struct {
        fn onStateChange(ptr: *anyopaque, _state: game.ResolvedState) void {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            self.onStateChange(_state);
        }
    };

    return &.{
        .onStateChange = vtable.onStateChange,
    };
}

pub const LocalClient = struct {
    allocator: Allocator,
    state: game.ResolvedState, // why cant this be a pointer?

    handlerPtr: *anyopaque,
    vtable: *const VTable,

    /// obj must implement the following function:
    /// fn onStateChange(self: *@This(), state: game.ResolvedState) void {}
    pub fn init(allocator: Allocator, start_event: events.StartGameEvent, obj: anytype) !LocalClient {
        var state = try game.ResolvedState.init(allocator, start_event);
        errdefer state.deinit(allocator);

        switch (start_event) {
            .withAi => |ev| {
                // ai makes the first move if needed
                if (ev.playerSide == .o) {
                    const pos = try Ai.getMove(ev.aiDifficulty, state.board);

                    try state.resolveEvent(.{
                        .makeMove = .{
                            .position = pos,
                        },
                    });
                }
            },
            .multiplayer => |ev| {
                // check that X must always be started
                if (ev.playerSide != .x) {
                    return error.InvalidSideInLocalMultiplayer;
                }
            },
        }
        // create callback binding manually
        // const Ptr = @TypeOf(obj);
        // const onStateChange = struct {
        //     fn cb(ptr: *anyopaque, _state: game.ResolvedState) void {
        //         const self: Ptr = @ptrCast(@alignCast(ptr));
        //         self.onStateChange(_state);
        //     }
        // }.cb;
        const vtable = createVTable(obj);
        // always emit state change at the start of the game
        vtable.onStateChange(obj, state);

        return .{
            .allocator = allocator,
            .state = state,
            .handlerPtr = obj,
            .vtable = vtable,
        };
    }

    pub fn deinit(self: *LocalClient) void {
        self.state.deinit(self.allocator);
        // self.state.* = undefined; // TODO: ive seen this somewhere, not sure if its needed
    }

    // this should really be handle move event... but whatevs

    pub fn handleEvent(self: *LocalClient, ev: events.Event) !void {
        try self.state.resolveEvent(ev);

        // make sure no moves are made when game is over
        if (self.state.mode == .withAi and self.state.status.isPlaying()) {
            const pos = try Ai.getMove(self.state.ai.?, self.state.board);

            try self.state.resolveEvent(.{
                .makeMove = .{
                    .position = pos,
                },
            });
        }
        self.vtable.onStateChange(self.handlerPtr, self.state);
    }
};

// try using this https://github.com/karlseguin/websocket.zig
// remote ai will emit events as it is
// the client should also be able to join a game instead of just starting it
pub const RemoteClient = struct {
    allocator: Allocator,
    connInfo: ConnectionInfo,
    state: game.ResolvedState,
    // todo onStateChange: *const fn (ctx: *anyopaque, state: game.ResolvedState) void,

    handlerPtr: *anyopaque,
    vtable: *const VTable,

    const ConnectionInfo = struct {
        serverUrl: []const u8,
        token: []const u8,
    };

    /// obj must implement the following function:
    /// fn onStateChange(self: *@This(), state: game.ResolvedState) void {}
    pub fn initStart(allocator: Allocator, conn_info: ConnectionInfo, start_event: events.StartGameEvent, obj: anytype) !RemoteClient {
        var state = try game.ResolvedState.init(allocator, start_event);
        errdefer state.deinit(allocator);

        // TODO: establish websockets

        switch (start_event) {
            .withAi => |ev| {
                // ai makes the first move if needed
                if (ev.playerSide == .O) {
                    const pos = try Ai.getMove(ev.aiDifficulty, state);

                    try state.resolveEvent(.{
                        .makeMove = .{
                            .position = pos,
                        },
                    });
                }
            },
            .multiplayer => |ev| {
                // check that X must always be started
                if (ev.playerSide != .X) {
                    return error.InvalidSideInLocalMultiplayer;
                }
            },
        }

        const vtable = createVTable(obj);

        return .{
            .allocator = allocator,
            .state = state,
            .connInfo = conn_info,
            .handlerPtr = obj,
            .vtable = vtable,
        };
    }

    // pub fn initJoin(allocator: Allocator, conn_info: ConnectionInfo, join_code: []const u8) !RemoteClient {

    // }
    // also need a function to init already running game?

    pub fn deinit(self: *RemoteClient) void {
        self.state.deinit(self.allocator);
        // self.state.* = undefined; // TODO: ive seen this somewhere, not sure if its needed
    }

    // this should really be handle move event... but whatevs

    pub fn handleEvent(self: *RemoteClient, ev: events.Event) !void {
        try self.state.resolveEvent(ev);

        if (self.state.mode == .withAi) {
            const pos = try Ai.getMove(self.state.ai.?, &self.state);

            try self.state.resolveEvent(.{
                .makeMove = .{
                    .position = pos,
                },
            });
        }
    }
};

const testing_allocator = testing.allocator;

const testGameHandler = struct {
    count: usize = 0,
    state: game.ResolvedState = undefined,

    fn onStateChange(self: *@This(), state: game.ResolvedState) void {
        // std.debug.print("state change happening. seqId: {d}\n", .{state.seqId});
        _ = state;
        self.count += 1;
    }

    pub fn setState(self: *@This(), state: game.ResolvedState) void {
        self.state = state;
    }
};

test LocalClient {
    var instance = testGameHandler{};
    var client = Client{
        .local = try LocalClient.init(
            testing_allocator,
            .{
                .withAi = .{ .aiDifficulty = .easy, .boardSize = 3, .playerSide = .o },
            },
            &instance,
        ),
    };

    defer client.deinit();

    // FIXME: use hard AI which will always make the best move in the center (its predictable)
    // for now dumest non-prod is used
    // or use easy ai with a initialization seed
    try testing.expectEqual(1, instance.count);
    try testing.expectEqual(.turnO, client.state().status);

    try testing.expectEqual(.x, client.state().board.getValue(.{ .x = 0, .y = 0 }));

    try client.handleEvent(.{ .makeMove = .{ .position = .{ .x = 1, .y = 1 } } });
    try testing.expectEqual(2, instance.count);
    try testing.expectEqual(.turnO, client.state().status);
    try testing.expectEqual(.o, client.state().board.getValue(.{ .x = 1, .y = 1 }));
    try testing.expectEqual(.x, client.state().board.getValue(.{ .x = 1, .y = 0 })); //CAREFUL!!! this is hardcoded for now

}

test "nested mutations" {
    var instance = testGameHandler{};
    var client = Client{
        .local = try LocalClient.init(
            testing_allocator,
            .{
                .multiplayer = .{ .boardSize = 3, .playerSide = .x },
            },
            &instance,
        ),
    };

    instance.setState(client.state());

    defer client.deinit();

    const stored = client.state(); // this is a const!!! ughhh

    // all pointer values are different...
    // std.debug.print("stored:\t\t{*}\nimmediate:\t{*}\ninstance:\t{*}\n\n", .{ &stored, &client.state(), &instance.state });

    try testing.expectEqual(client.state().board.grid[0][0], .empty);

    client.state().board.grid[0][0] = .x;

    try testing.expectEqual(stored.board.grid[0][0], .x);
    try testing.expectEqual(client.state().board.grid[0][0], .x);
    try testing.expectEqual(instance.state.board.grid[0][0], .x);

    // std.debug.print("stored:\t\t{*}\nimmediate:\t{*}\ninstance:\t{*}\n\n", .{ &stored, &client.state(), &instance.state });

    // try instance.state.board.setValue(.{1,1}, .O);
    instance.state.board.grid[1][1] = .o;

    try testing.expectEqual(stored.board.grid[1][1], .o);
    try testing.expectEqual(client.state().board.grid[1][1], .o);
    try testing.expectEqual(instance.state.board.grid[1][1], .o);

    // std.debug.print("stored:\t\t{*}\nimmediate:\t{*}\ninstance:\t{*}\n\n", .{ &stored, &client.state(), &instance.state });

    // i am so confused
    // am I copying memory as nothing is passed by the pointer? but then why can I mutate it?
    // what is the end result is a struct, zig cannot copy it without an allocator, so it must be passed by reference?
    // good article, needs more in-depth reading
    // https://akhil.sh/tutorials/zig/zig/pointers_in_zig/
}
