const std = @import("std");
const testing = std.testing;
const AnyWriter = std.io.AnyWriter;
const AnyReader = std.io.AnyReader;

const game = @import("../game.zig");
const input = @import("input.zig");
const events = @import("../events.zig");
// const client = @import("../client.zig");
const render = @import("renderer.zig").render;
const GameState = @import("../GameState.zig");
const Event = @import("../events.zig").Event;

pub const GameHandler = struct {
    reader: AnyReader,
    writer: AnyWriter,

    nav: input.Navigation,
    state: *GameState,

    playing: bool = true,

    pub fn init(reader: AnyReader, writer: AnyWriter, state: *GameState) GameHandler {
        // state needs an original game start event
        // this is annoything
        return .{
            .reader = reader,
            .writer = writer,
            .nav = input.Navigation.init(state.board.size),
            .state = state,
        };
    }

    pub fn onEvent(self: *GameHandler, event: Event) void {
        // will be triggered by out GameServer thingy

        // no events are actually published here
        // its only whats coming from the state...

        switch (event) {
            .__runtimeError => |ev| render(self.writer, self.state, self.nav.pos, ev) catch |err| {
                // I must capture this
                std.debug.print("FAILED TO RENDER with error {any}\n", .{err});
                self.playing = false;
            },
            else => render(self.writer, self.state, self.nav.pos, null) catch |err| {
                // I must capture this
                std.debug.print("FAILED TO RENDER {any}\n", .{err});
                self.playing = false;
            },
        }
        self.writer.print("state published an event: {any}\n", .{event}) catch unreachable;

        const game_over = self.state.status.isGameOver();

        if (game_over) {
            self.writer.print("Game over. Status: {any}\n", .{self.state.status}) catch unreachable;
            self.playing = false;
        }
    }

    // make run to be more like "onInput"
    // pub fn onInput(cmd: input.CliCommand) void {

    // }

    // run can be moved out... but then its not pretty...
    pub fn run(self: *GameHandler) !void {
        // TODO: fix hacky hack, this will never stop, if the response from the server is async
        // which is the case when remote server is used

        try render(self.writer, self.state, self.nav.pos, null);

        while (self.playing) {
            const cmd = try input.readCommand(self.reader);

            switch (cmd) {
                .Quit => {
                    try self.writer.print("Quitting...\n", .{});
                    return;
                },
                .Select => {
                    // ah, now I need a side:D, so this game client needs to know who I am playing as
                    // and if its multiplayer, this needs to be switched...
                    // TODO: unhardcode multiplayer behavior?
                    const ev = events.Event{ .moveMade = .{
                        .position = self.nav.pos,
                        .side = self.state.current_player,
                    } };

                    self.state.handleEvent(ev, self, true) catch |err| {
                        // this is not done on the game level yet
                        self.onEvent(.{
                            .__runtimeError = Event.RuntimeError.fromError(err),
                        });
                        continue;
                    };

                    try render(self.writer, self.state, self.nav.pos, null);
                },
                else => |nav_cmd| {
                    switch (nav_cmd) {
                        .Left => self.nav.onDir(.Left),
                        .Right => self.nav.onDir(.Right),
                        .Up => self.nav.onDir(.Up),
                        .Down => self.nav.onDir(.Down),
                        else => unreachable,
                    }
                    // self.nav.onDir(nav_cmd);
                    // force the rerender
                    try render(self.writer, self.state, self.nav.pos, null);
                },
            }
        }
    }
};
