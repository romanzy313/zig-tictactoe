const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const game = @import("game.zig");
const events = @import("events.zig");
const Ai = @import("Ai.zig");

/// this is a game client!
/// `LocalClient` emulates server with ai, even history is not stored for now
/// `RemoteClient` will use websockets and sync that way, but unsure how callback based rendering is done
pub const Client = union(enum) {
    // should the allocator be stored here?

    local: LocalClient,
    remote: RemoteClient,

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
        switch (self.*) {
            inline else => |case| return case.state,
        }
    }
};

pub const LocalClient = struct {
    allocator: Allocator,
    state: game.ResolvedState, // why cant this be a pointer?

    pub fn init(allocator: Allocator, start_event: events.StartGameEvent) !LocalClient {
        var state = try game.ResolvedState.init(allocator, start_event);
        errdefer state.deinit(allocator);

        switch (start_event) {
            .withAi => |ev| {
                // ai makes the first move if needed
                if (ev.playerSide == .O) {
                    const pos = try Ai.getMove(ev.aiDifficulty, &state);

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

        return .{
            .allocator = allocator,
            .state = state,
        };
    }

    pub fn deinit(self: *LocalClient) void {
        self.state.deinit(self.allocator);
        // self.state.* = undefined; // TODO: ive seen this somewhere, not sure if its needed
    }

    // this should really be handle move event... but whatevs

    pub fn handleEvent(self: *LocalClient, ev: events.Event) !void {
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

// try using this https://github.com/karlseguin/websocket.zig
pub const RemoteClient = struct {
    allocator: Allocator,
    connInfo: ConnectionInfo,
    state: game.ResolvedState,

    const ConnectionInfo = struct {
        serverUrl: []const u8,
        token: []const u8,
    };

    pub fn init(allocator: Allocator, conn_info: ConnectionInfo, start_event: events.StartGameEvent) !RemoteClient {
        var state = try game.ResolvedState.init(allocator, start_event);
        errdefer state.deinit(allocator);

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

        // TODO: establish websockets

        return .{
            .allocator = allocator,
            .state = state,
            .connInfo = conn_info,
        };
    }

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
test LocalClient {
    var client = Client{
        .local = try LocalClient.init(
            testing_allocator,
            .{
                .withAi = .{ .aiDifficulty = .easy, .boardSize = 3, .playerSide = .O },
            },
        ),
    };

    defer client.deinit();

    // FIXME: use hard AI which will always make the best move in the center (its predictable)
    // for now dumest non-prod is used
    // or use easy ai with a initialization seed
    try testing.expectEqual(.TurnO, client.state().status);
    try testing.expectEqual(.X, client.state().grid[0][0]);

    try client.handleEvent(.{ .makeMove = .{ .position = .{ .x = 1, .y = 1 } } });
    try testing.expectEqual(.TurnO, client.state().status);
    try testing.expectEqual(.O, client.state().grid[1][1]);
    try testing.expectEqual(.X, client.state().grid[0][1]); // this is hardcoded for now

    // I can mutate the original... how wierd, its not a pointer, but it has self *ResolvedState...
    // client.state().grid[1][1] = .O;
    // client.state().grid[2][2] = .X;
    // var state = client.state();
    // state.debugPrint();
}
