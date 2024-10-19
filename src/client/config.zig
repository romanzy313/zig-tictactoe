const std = @import("std");
const debug = std.debug;
const Allocator = std.mem.Allocator;

const game = @import("common").game;
const ai = @import("common").ai;

/// Configuration for the application
pub const Config = struct {
    aiDifficulty: ?ai.Difficulty,

    pub fn debugPrint(self: Config) void {
        debug.print("AI Difficulty: {any}\n", .{self.aiDifficulty});
    }
};

pub fn parseConfigFromArgs(allocator: Allocator) !Config {
    var config = Config{
        .aiDifficulty = null,
    };

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len >= 2 and std.mem.eql(u8, args[1], "help")) {
        debug.print(
            \\Help message here
            \\
        , .{});
        return std.process.exit(0);
    }

    outer: for (args, 0..) |arg, i| {
        // debug.print("parsing {s}\n", .{arg});
        if (std.mem.eql(u8, arg, "--ai")) {
            // assume next arg is present for now
            const aiVal = args[i + 1];

            // inline for (std.meta.fields(ai.Difficulty)) |f| {
            //     std.debug.print("{} {}\n", .{f.value});
            // }
            // cannot switch on strings...
            inline for (@typeInfo(ai.Difficulty).Enum.fields) |f| {
                // std.debug.print("{d} {s}\n", .{ f.value, f.name });
                if (std.mem.eql(u8, f.name, aiVal)) {
                    config.aiDifficulty = @enumFromInt(f.value);

                    continue :outer;
                }
            }

            return error.BadAiArg;
        }
        // add more parameters on here
        // not elegant, but it works
    }
    return config;
}
