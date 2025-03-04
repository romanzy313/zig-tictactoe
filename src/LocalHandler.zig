const std = @import("std");
const testing = std.testing;

const game = @import("game.zig");
const events = @import("events.zig");
// const client = @import("client.zig");
const GameState = @import("GameState.zig");
const Event = @import("events.zig").Event;
const Board = @import("Board.zig");

pub const HandlerEvent = union(enum) {
    select: Board.CellPosition,
    rerender: void,
};

// I want this to be interface independent, huh
// so i must pass all this to the renderer and stuff
// This is "AppHandler", it deals with the state. It gets sent events from the outside
//
// 2 functions are passed:
//   render() to update the ui
//   publisher is anytype, but its also needed

pub fn LocalGameHandler(
    comptime IRenderer: type,
    comptime renderFn: *const fn (T: *IRenderer, state: *GameState, maybe_err: ?Event.RuntimeError) anyerror!void,
    // TODO: also add the publisher? because the game publisher needs to either be local or remote.
) type {
    return struct {
        const Self = @This();

        ptr: *IRenderer,
        state: *GameState,
        maybe_error: ?Event.RuntimeError = null,

        is_playing: bool = true,

        // wrap the IRenderer
        fn render(self: *Self) anyerror!void {
            try renderFn(self.ptr, self.state, self.maybe_error);
        }

        pub fn init(ptr: *IRenderer, state: *GameState) Self {
            return .{
                .ptr = ptr,
                .state = state,
            };
        }

        // this should never throw?
        pub fn tick(self: *Self, value: HandlerEvent) !void {
            switch (value) {
                .rerender => {},
                else => {
                    // reset error only when action was taken
                    self.maybe_error = null;
                },
            }

            switch (value) {
                .select => |position| {
                    const ev = events.Event{ .moveMade = .{
                        .position = position,
                        .side = self.state.current_player,
                    } };

                    // self here only works for the local multiplayer
                    // this requires that Self has a function onEvent... Very much misdirection...
                    self.state.handleEvent(ev, self, true) catch |err| {
                        self.onEvent(.{
                            .__runtimeError = Event.RuntimeError.fromError(err),
                        });
                        return;
                    };
                    try self.render();
                },
                .rerender => {
                    try self.render();
                },
            }
        }

        pub fn onEvent(self: *Self, event: Event) void {
            switch (event) {
                .__runtimeError => |runtime_error| {
                    self.maybe_error = runtime_error;
                    self.render() catch |err| {
                        // I must capture this
                        std.debug.print("FAILED TO RENDER with error {any}\n", .{err});
                    };
                },
                .gameFinished => {
                    self.maybe_error = null;
                    self.is_playing = false;
                },
                else => {
                    // reset error on any other event
                    // but these are currently self-emitted events for ai and stuff. in the future server will emit them instead
                    self.maybe_error = null;
                    self.render() catch |err| {
                        std.debug.print("FAILED TO RENDER {any}\n", .{err});
                    };
                },
            }

            // const game_over = self.state.status.isGameOver();

            // if (game_over) {
            //     self.is_playing = false;
            // }
        }
    };
}
