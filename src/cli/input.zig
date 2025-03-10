const std = @import("std");
const fs = std.fs;
const linux = std.os.linux;
const control_code = std.ascii.control_code;
const testing = std.testing;
const game = @import("../game.zig");
const Board = @import("../Board.zig");

pub const CliCommand = enum {
    // None,
    Quit,
    Select,
    Left,
    Down,
    Up,
    Right,
};

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

pub const Navigation = struct {
    pub const Direction = enum {
        Left,
        Down,
        Up,
        Right,
    };

    gridSize: usize,
    pos: Board.CellPosition,

    pub fn init(gridSize: usize) Navigation {
        const half = @divFloor(gridSize, 2);
        return .{
            .gridSize = gridSize,
            .pos = .{
                .x = half,
                .y = half,
            },
        };
    }

    pub fn onDir(self: *Navigation, dir: Direction) void {
        // var pos = self.pos.*;
        switch (dir) {
            .Left => {
                if (self.pos.x > 0) self.pos.x -= 1;
            },
            .Right => {
                if (self.pos.x < self.gridSize - 1) self.pos.x += 1;
            },
            .Up => {
                if (self.pos.y > 0) self.pos.y -= 1;
            },
            .Down => {
                if (self.pos.y < self.gridSize - 1) self.pos.y += 1;
            },
        }
    }

    pub fn setPos(self: *Navigation, pos: Board.CellPosition) void {
        self.pos.x = pos.x;
        self.pos.y = pos.y;
    }
};

test Navigation {
    var nav = Navigation.init(3);

    try testing.expectEqual(1, nav.pos.x);

    nav.onDir(.Up);
    try testing.expectEqual(1, nav.pos.x);
    try testing.expectEqual(0, nav.pos.y);

    nav.onDir(.Up);
    // WARNING: this provides really bad feedback on error.
    try testing.expectEqual(Board.CellPosition{ .x = 1, .y = 0 }, nav.pos);
}

// source https://blog.fabrb.com/2024/capturing-input-in-real-time-zig-0-14/
// mouse trap https://stackoverflow.com/questions/5966903/how-to-get-mousemove-and-mouseclick-in-bash
pub const RawMode = struct {
    tty_fd: fs.File.Handle = undefined,
    old_settings: linux.termios = undefined,
    mouse_trap: bool,

    pub fn init(mouse_trap: bool) !RawMode {
        const tty_file = try fs.openFileAbsolute("/dev/tty", .{});
        const tty_fd = tty_file.handle;

        var old_settings: linux.termios = undefined;
        _ = linux.tcgetattr(tty_fd, &old_settings);

        var new_settings: linux.termios = old_settings;
        new_settings.lflag.ICANON = false;
        new_settings.lflag.ECHO = false;

        _ = linux.tcsetattr(tty_fd, linux.TCSA.NOW, &new_settings);

        if (mouse_trap) {
            // send output to stdout?
        }

        return .{
            .tty_fd = tty_fd,
            .old_settings = old_settings,
            .mouse_trap = mouse_trap,
        };
    }

    pub fn deinit(self: RawMode) void {
        _ = linux.tcsetattr(self.tty_fd, linux.TCSA.NOW, &self.old_settings);
    }
};
