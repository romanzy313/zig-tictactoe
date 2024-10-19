const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const control_code = std.ascii.control_code;
const fs = std.fs;
const linux = std.os.linux;

const game = @import("game.zig");
const server = @import("server.zig");
const Ai = @import("ai.zig").Ai;
const Navigation = @import("input.zig").Navigation;

pub const CliCommand = enum {
    // None,
    Quit,
    Select,
    Left,
    Down,
    Up,
    Right,
};

// https://stackoverflow.com/questions/4842424/list-of-ansi-color-escape-sequences
const ANSI_NORMAL: []const u8 = "\u{001b}[0m";
const ANSI_SELECTED: []const u8 = "\u{001b}[7m";
const CLEAR_TERM: []const u8 = "\x1b[2J\x1b[H";

pub fn mainLoop(serv: server.UniversalServer) !void {
    const raw = try RawMode.init();
    defer raw.deinit();
    const stdin = std.io.getStdIn().reader().any();
    const stdout = std.io.getStdOut().writer().any();

    // get own copy of the state from the iniversal server?

    var localState = serv.stateCopy();

    var nav = Navigation.init(game.GAME_SIZE, game.STARTING_POSITION);

    // render the copy...
    try render(stdout, &localState, nav.pos, null);

    while (true) {
        const cmd = try readCommand(stdin);

        switch (cmd) {
            .Quit => {
                try stdout.print("Quitting...\n", .{});
                return;
            },
            .Select => {
                // errors are not handled, application will crash
                const res = try serv.handleRequest(.{
                    .makeMove = nav.pos,
                });

                localState = res.stateUpdate;

                try render(stdout, &localState, nav.pos, null);

                const isPlaying = localState.status.isPlaying();
                if (!isPlaying) {
                    break;
                }
            },
            .Left => nav.onDir(.Left),
            .Right => nav.onDir(.Right),
            .Up => nav.onDir(.Up),
            .Down => nav.onDir(.Down),
        }
        try render(stdout, &localState, nav.pos, null);
    }

    try render(stdout, &localState, nav.pos, null);
    try stdout.print("Game over. Status: {any}\n", .{localState.status});
}

pub fn render(writer: std.io.AnyWriter, state: *game.State, selection: game.CellPosition, err: ?anyerror) !void {
    try writer.writeAll(CLEAR_TERM);

    for (state.grid, 0..) |row, i| {
        for (row, 0..) |cell, j| {
            const ansiPrefix = if (selection.y == i and selection.x == j) ANSI_SELECTED else ANSI_NORMAL;
            switch (cell) {
                .Empty => try writer.print("{s}-{s}", .{ ansiPrefix, ANSI_NORMAL }),
                .X => try writer.print("{s}x{s}", .{ ansiPrefix, ANSI_NORMAL }),
                .O => try writer.print("{s}o{s}", .{ ansiPrefix, ANSI_NORMAL }),
            }
            try writer.writeAll(" ");
        }
        try writer.writeAll("\n");
    }

    // handle state accordingly.
    switch (state.status) {
        .TurnX => try writer.print("Player X turn\n", .{}),
        .TurnO => try writer.print("Player O turn\n", .{}),
        .WinX => try writer.print("Player X won\n", .{}),
        .WinO => try writer.print("Player O won\n", .{}),
        .Stalemate => try writer.print("Stalemate\n", .{}),
    }

    if (err == null) {
        try writer.print("\n", .{});
    } else {
        try writer.print("error: {any}\n", .{err});
    }

    // try writer.print("pos: {any}", .{selection});
}

pub fn readCommand(reader: std.io.AnyReader) !CliCommand {
    var buffer: [3]u8 = undefined;
    const n = try reader.read(buffer[0..1]);

    if (n == 0) {
        std.debug.print("nothing was read", .{});

        return readCommand(reader); // recurse?
    }

    const input = buffer[0];

    switch (input) {
        // 10, 32; where 0x20 is space...
        control_code.lf, 0x20 => return .Select,
        'q' => return .Quit,
        'h', 'a' => return .Left,
        'j', 's' => return .Down,
        'k', 'w' => return .Up,
        'l', 'd' => return .Right,
        // or use 27, thats escape
        control_code.esc => {
            // Handle escape sequences for arrow keys
            const seq_read = try reader.read(buffer[1..2]);

            if (seq_read != 0 and buffer[1] == '[') {
                _ = try reader.read(buffer[2..3]);

                switch (buffer[2]) {
                    'A' => return .Up,
                    'B' => return .Down,
                    'C' => return .Right,
                    'D' => return .Left,
                    else => {
                        std.debug.print("Unrecognized input: '{}'\n", .{buffer[2]});
                    },
                }
            }
        },
        else => {
            std.debug.print("Unrecognized input: '{}'\n", .{input});
        },
    }

    return try readCommand(reader);
}

// source https://blog.fabrb.com/2024/capturing-input-in-real-time-zig-0-14/
pub const RawMode = struct {
    tty_fd: fs.File.Handle = undefined,
    old_settings: linux.termios = undefined,

    pub fn init() !RawMode {
        const tty_file = try fs.openFileAbsolute("/dev/tty", .{});
        const tty_fd = tty_file.handle;

        var old_settings: linux.termios = undefined;
        _ = linux.tcgetattr(tty_fd, &old_settings);

        var new_settings: linux.termios = old_settings;
        new_settings.lflag.ICANON = false;
        new_settings.lflag.ECHO = false;

        _ = linux.tcsetattr(tty_fd, linux.TCSA.NOW, &new_settings);

        return .{
            .tty_fd = tty_fd,
            .old_settings = old_settings,
        };
    }

    pub fn deinit(self: RawMode) void {
        _ = linux.tcsetattr(self.tty_fd, linux.TCSA.NOW, &self.old_settings);
    }
};
