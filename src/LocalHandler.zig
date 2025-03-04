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
) type {
    return struct {
        const Self = @This();

        ptr: *IRenderer,
        state: *GameState,

        is_playing: bool = true,

        pub fn render(self: *Self, maybe_err: ?Event.RuntimeError) anyerror!void {
            try renderFn(self.ptr, self.state, maybe_err);
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
                    try self.render(null);
                },
            }
        }

        pub fn onEvent(self: *Self, event: Event) void {
            switch (event) {
                .__runtimeError => |runtime_error| self.render(runtime_error) catch |err| {
                    // I must capture this
                    std.debug.print("FAILED TO RENDER with error {any}\n", .{err});
                    self.is_playing = false;
                },
                // .gameFinished => {
                //     std.debug.print("GAME WAS FINISHED\n", .{});
                // },
                else => self.render(null) catch |err| {
                    // I must capture this
                    std.debug.print("FAILED TO RENDER {any}\n", .{err});
                    self.is_playing = false;
                },
            }

            const game_over = self.state.status.isGameOver();

            if (game_over) {
                // this also needs to be passed to the renderer, or renderer needs to be aware if game is over or not!
                // self.writer.print("Game over. Status: {any}\n", .{self.state.status}) catch unreachable;
                self.is_playing = false;
            }
        }
    };
}
