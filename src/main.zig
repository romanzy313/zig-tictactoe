const std = @import("std");
const Board = @import("board.zig").Board;
const Input = @import("input.zig");
const math = @import("math.zig");

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

    try input.clearScreen(stdout);

    // two ways to parse args
    // source https://ziggit.dev/t/read-command-line-arguments/220/7
    var args = std.process.args();
    _ = args.skip(); //to skip the zig call

    while (args.next()) |arg| {
        try stdout.print("{s}, ", .{arg});
    }
    try stdout.print("\n\n", .{});

    for (std.os.argv[1..]) |arg| {
        std.debug.print("  {s}\n", .{arg});
    }
    try stdout.print("\n\n", .{});

    // TODO: depend on who goes first
    var playerPos = Board.CellPosition{ .x = 1, .y = 1 };
    var currentPlayer = Board.Player.X;

    try board.printWithSelection(stdout, playerPos);

    while (true) {
        const cmd = try input.getCommand(stdin);

        switch (cmd) {
            Input.Command.Quit => {
                try stdout.print("Quitting...\n", .{});
                return;
            },

            Input.Command.Left => {
                // if (playerPos.x > 0) playerPos.x -= 1;
                if (playerPos.y > 0) playerPos.y -= 1;
            },
            Input.Command.Right => {
                if (playerPos.y < 2) playerPos.y += 1;
            },
            Input.Command.Down => {
                if (playerPos.x < 2) playerPos.x += 1;
            },
            Input.Command.Up => {
                if (playerPos.x > 0) playerPos.x -= 1;
            },
            // TODO handle the rest
            Input.Command.Select => {
                board.makeMove(currentPlayer, playerPos) catch |e| {
                    try stdout.print("error: {any}\n", .{e});
                    continue;
                };

                const cond = board.state();

                // woops, this gets cleared...
                switch (cond) {
                    .Stalemate => try stdout.print("outcome: stalemate\n", .{}),
                    .WinX => try stdout.print("outcome: x won (you)\n", .{}),
                    .WinO => try stdout.print("outcome: o won (ai)\n", .{}),
                    else => {},
                }

                if (currentPlayer == .X) currentPlayer = .O else currentPlayer = .X;
            },
            else => {
                // std.debug.print("doint nothing", args: anytype)

                std.debug.print("Got command {}\n", .{cmd});
                continue;
            },
        }

        // simply redraw on every frame
        try input.clearScreen(stdout);
        try board.printWithSelection(stdout, playerPos);
        try stdout.print("game state {any}\n", .{board.state()});
    }
}
