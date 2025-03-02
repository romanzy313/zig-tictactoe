const std = @import("std");
const testing = std.testing;
const AnyWriter = std.io.AnyWriter;
const AnyReader = std.io.AnyReader;

const game = @import("../game.zig");
const input = @import("input.zig");
const events = @import("../events.zig");
// const client = @import("../client.zig");
const renderer = @import("renderer.zig");
const GameState = @import("../GameState.zig");
const Event = @import("../events.zig").Event;
const Board = @import("../Board.zig");

pub const HandlerEvent = union(enum) {
    select: Board.CellPosition,
    hover: Board.CellPosition,
};

// I want this to be interface independent, huh
// so i must pass all this to the renderer and stuff
// This is "AppHandler", it deals with the state. It gets sent events from the outside
//
// 2 functions are passed:
//   render() to update the ui
//   publisher is anytype, but its also needed
pub const GameHandler = struct {
    writer: AnyWriter,

    state: *GameState,
    cursor_pos: Board.CellPosition,

    is_playing: bool = true,

    // pass in initial cursor position to init?
    pub fn init(writer: AnyWriter, state: *GameState) GameHandler {
        return .{
            .writer = writer,
            .state = state,
            .cursor_pos = Board.CellPosition{ .x = 0, .y = 0 },
        };
    }

    // this is for the state... too bad the name is hardcoded
    // and too bad it has to be public...
    pub fn onEvent(self: *GameHandler, event: Event) void {
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
            self.writer.print("Game over. Status: {any}\n", .{self.state.status}) catch unreachable;
            self.is_playing = false;
        }
    }

    pub fn render(self: *GameHandler, maybe_err: ?Event.RuntimeError) !void {
        try renderer.render(self.writer, self.state, self.cursor_pos, maybe_err);
    }

    // TODO
    // pub fn handleEventFromServer(self: *GameHandler, ev: Event) {
    //     const mockPublisher = null;

    //     self.state.handleEvent(ev, self, true) catch |err| {
    //         self.onEvent(.{
    //             .__runtimeError = Event.RuntimeError.fromError(err),
    //         });
    //         return;
    //     };
    //     try self.render(null);
    //     // the publisher becomes self?
    //     // because this will need to publish things... oh the publisher is provided
    // }

    // returns false when done
    pub fn tick(self: *GameHandler, value: HandlerEvent) !void {
        switch (value) {
            .select => |position| {
                self.cursor_pos = position;

                const ev = events.Event{ .moveMade = .{
                    .position = self.cursor_pos,
                    .side = self.state.current_player,
                } };

                // self here only works for the local multiplayer
                self.state.handleEvent(ev, self, true) catch |err| {
                    self.onEvent(.{
                        .__runtimeError = Event.RuntimeError.fromError(err),
                    });
                    return;
                };
                try self.render(null);
            },
            .hover => |position| {
                // purely local state
                self.cursor_pos = position;
                try self.render(null);
            },
        }
    }
};
