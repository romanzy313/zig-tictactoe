const std = @import("std");
const Board = @import("board.zig").Board;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer().any();
    // const stdin = std.io.getStdIn().reader();

    var board = try Board.init(allocator, 3);
    defer board.deinit();

    try board.print(stdout);
    try stdout.writeAll("\n\n");

    try board.makeMove(Board.Player.X, Board.CellPosition{ .x = 1, .y = 1 });

    try board.print(stdout);
    try stdout.writeAll("\n\n");

    try stdout.print("Game state: {s}\n", .{@tagName(board.state())});
}
