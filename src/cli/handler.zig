const std = @import("std");
const testing = std.testing;

const game = @import("common").game;
const input = @import("input.zig");
const events = @import("common").events;
const client = @import("common").client;
const render = @import("renderer.zig").render;

pub const GameHandler = struct {
    reader: std.io.AnyReader,
    writer: std.io.AnyWriter,

    clientInstance: client.Client = undefined,
    nav: input.Navigation,

    playing: bool = true,

    pub fn init(reader: std.io.AnyReader, writer: std.io.AnyWriter, board_size: usize) GameHandler {
        return .{
            .reader = reader,
            .writer = writer,
            .nav = input.Navigation.init(board_size, .{ .x = 1, .y = 1 }),
        };
    }

    pub fn setClient(self: *GameHandler, client_instance: client.Client) void {
        self.clientInstance = client_instance;
    }

    pub fn onStateChange(self: *GameHandler, state: game.ResolvedState) void {
        // this will not work, as main thread is blocked...
        render(self.writer, state, self.nav.pos, null) catch |err| {
            // render with error?
            // this technically can never fail, if we cant render into stdout - its fatal error
            std.debug.print("FAILED TO RENDER {any}\n", .{err});
            self.playing = false;
        };
        const game_over = !state.status.isPlaying();

        if (game_over) {
            self.writer.print("Game over. Status: {any}\n", .{self.clientInstance.state().status}) catch unreachable;
            self.playing = false;
        }
    }

    // run can be moved out... but then its not pretty...
    pub fn run(self: *GameHandler) !void {
        // TODO: fix hacky hack, this will never stop, if the response from the server is async
        // which is the case when remote server is used
        while (self.playing) {
            const cmd = try input.readCommand(self.reader);

            std.debug.print("got command {any}\n", .{cmd});

            switch (cmd) {
                .Quit => {
                    try self.writer.print("Quitting...\n", .{});
                    return;
                },
                .Select => {
                    // errors are not handled, application will crash
                    const ev = events.Event{ .makeMove = .{ .position = self.nav.pos } };

                    try self.clientInstance.handleEvent(ev);
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
                    try render(self.writer, self.clientInstance.state(), self.nav.pos, null);
                },
                // .Left => self.nav.onDir(.Left),
                // .Right => self.nav.onDir(.Right),
                // .Up => self.nav.onDir(.Up),
                // .Down => self.nav.onDir(.Down),
            }
            // try render(stdout, &localState, nav.pos, null);
        }

        // try render(stdout, &localState, nav.pos, null);

    }
};
