const std = @import("std");
const fs = std.fs;
const linux = std.os.linux;

pub const Command = enum { None, Quit, Select, Left, Down, Up, Right };

pub const CliInput = struct {
    tty_fd: fs.File.Handle = undefined,
    old_settings: linux.termios = undefined,

    pub fn init() !CliInput {
        // source https://blog.fabrb.com/2024/capturing-input-in-real-time-zig-0-14/
        const tty_file = try fs.openFileAbsolute("/dev/tty", .{});
        const tty_fd = tty_file.handle;

        var old_settings: linux.termios = undefined;
        _ = linux.tcgetattr(tty_fd, &old_settings);

        var new_settings: linux.termios = old_settings;
        new_settings.lflag.ICANON = false;
        new_settings.lflag.ECHO = false;

        _ = linux.tcsetattr(tty_fd, linux.TCSA.NOW, &new_settings);

        return .{ .tty_fd = tty_fd, .old_settings = old_settings };
    }
    pub fn deinit(self: CliInput) void {
        _ = linux.tcsetattr(self.tty_fd, linux.TCSA.NOW, &self.old_settings);
    }

    pub fn getCommand(self: CliInput, reader: std.io.AnyReader) !Command {
        _ = self;
        const debug = std.debug;

        var buffer: [3]u8 = undefined;
        const n = try reader.read(buffer[0..1]);

        if (n == 0) return Command.None; // Nothing read

        const input = buffer[0];

        switch (input) {
            10, 32 => {
                return Command.Select;
            },

            'q' => {
                // try debug.print("Quitting...\n", .{});
                return Command.Quit;
            },
            'h', 'j', 'k', 'l' => {
                debug.print("Received '{}'\n", .{input});
                // Handle hjkl movement
                switch (input) {
                    'h' => return Command.Left,
                    'j' => return Command.Down,
                    'k' => return Command.Up,
                    'l' => return Command.Right,
                    else => {
                        debug.print("Unrecognized input: '{}'\n", .{input});
                    },
                }
            },
            // or use 27, thats escape
            '\x1B' => {
                // Handle escape sequences for arrow keys
                const seq_read = try reader.read(buffer[1..2]);

                if (seq_read != 0 and buffer[1] == '[') {
                    _ = try reader.read(buffer[2..3]);

                    switch (buffer[2]) {
                        'A' => return Command.Up,
                        'B' => return Command.Down,
                        'C' => return Command.Right,
                        'D' => return Command.Left,
                        else => {
                            debug.print("Unrecognized input: '{}'\n", .{buffer[2]});
                        },
                    }
                }
            },
            else => {
                debug.print("Unrecognized input: '{}'\n", .{input});
            },
        }

        return Command.None;
    }

    pub fn clearScreen(self: CliInput, writer: std.io.AnyWriter) !void {
        _ = self;

        try writer.writeAll("\x1b[2J");
    }
};
