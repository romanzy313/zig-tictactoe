const std = @import("std");
const Board = @import("board.zig").Board;
const Input = @import("input.zig");
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer().any();
    const stdin = std.io.getStdIn().reader().any();

    var board = try Board.init(allocator, 3);
    defer board.deinit();

    const input = try Input.CliInput.init();
    defer input.deinit();

    try board.print(stdout);
    try stdout.writeAll("\n\n");

    try board.makeMove(Board.Player.X, Board.CellPosition{ .x = 1, .y = 1 });

    try board.print(stdout);
    try stdout.writeAll("\n\n");

    try stdout.print("Game state: {s}\n", .{@tagName(board.state())});

    while (true) {
        const cmd = try input.getCommand(stdin);

        switch (cmd) {
            Input.Command.Quit => {
                try stdout.print("Quitting...\n", .{});
                return;
            },
            Input.Command.Left, Input.Command.Down, Input.Command.Up, Input.Command.Right => {
                // handle inputs
            },
            // TODO handle the rest
            Input.Command.Select => {},
            else => {
                // std.debug.print("doint nothing", args: anytype)

                std.debug.print("Got command {}\n", .{cmd});
            },
        }
    }
}
