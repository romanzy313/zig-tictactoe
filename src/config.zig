const std = @import("std");
const testing = std.testing;
const fmt = std.fmt;
const debug = std.debug;
const Allocator = std.mem.Allocator;

const game = @import("game.zig");
const Ai = @import("Ai.zig");

const default_host = "localhost";
const default_port: u16 = 5432;

// TODO: dont use custom iterator, use ducktyped one

pub const RenderMode = enum { cli, gui };

pub const AppConfig = union(enum) {
    local: struct {
        renderMode: RenderMode,

        aiDifficulty: ?Ai.Difficulty,
    },
    remoteNew: struct {
        renderMode: RenderMode,

        aiDifficulty: ?Ai.Difficulty,
        host: []const u8,
        port: u16,
    },
    remoteJoin: struct {
        renderMode: RenderMode,

        code: []const u8,
        host: []const u8,
        port: u16,
    },

    pub fn renderMode(self: AppConfig) RenderMode {
        switch (self) {
            inline else => |case| return case.renderMode,
        }
    }
};

const helpMessage =
    \\how to use:
    \\remote new - create new game on the remote
    \\remote join <code> - join a remote game with invite code
    \\local - start a local game. pass --ai <difficulty> to enable AI
    \\global flags
    \\    --gui   enables gui rendering
;
const defaultRenderMode: RenderMode = .cli;
const defaultAIDifficulty: Ai.Difficulty = .easy;

pub fn parseConfig(allocator: Allocator, args: [][]u8) !AppConfig {
    _ = allocator;

    var iter = MyIterator{
        .strings = args,
    };

    if (iter.next()) |first| {
        if (std.mem.eql(u8, first, "help")) {
            debug.print(helpMessage, .{});
            return std.process.exit(0);
        } else if (std.mem.eql(u8, first, "remote")) {
            std.debug.panic("temporary removed", .{});
            if (iter.next()) |second| {
                if (std.mem.eql(u8, second, "new")) {

                    // parse them out
                    var config = AppConfig{
                        .remoteNew = .{
                            .aiDifficulty = null,
                            .host = default_host,
                            .port = default_port,
                        },
                    };

                    while (iter.next()) |next| {
                        if (std.mem.eql(u8, next, "--ai")) {
                            // get the value
                            if (iter.next()) |diff| {
                                config.remoteNew.aiDifficulty = try Ai.Difficulty.fromString(diff);
                            }
                        } else if (std.mem.eql(u8, next, "--host")) {
                            if (iter.next()) |host| {
                                config.remoteNew.host = host;
                            }
                        } else if (std.mem.eql(u8, next, "--port")) {
                            if (iter.next()) |port_str| {
                                config.remoteNew.port = try fmt.parseInt(u16, port_str, 10);
                            }
                        }
                    }
                    return config;
                } else if (std.mem.eql(u8, second, "join")) {
                    var config = AppConfig{
                        .remoteJoin = .{
                            .code = "",
                            .host = default_host,
                            .port = default_port,
                        },
                    };

                    if (iter.next()) |code| {
                        config.remoteJoin.code = code;
                    } else {
                        return error.MissingJoinCode;
                    }

                    while (iter.next()) |next| {
                        if (std.mem.eql(u8, next, "--host")) {
                            if (iter.next()) |host| {
                                config.remoteJoin.host = host;
                            }
                        } else if (std.mem.eql(u8, next, "--port")) {
                            if (iter.next()) |port_str| {
                                config.remoteJoin.port = try fmt.parseInt(u16, port_str, 10);
                            }
                        }
                    }
                    return config;
                }
            }
        } else if (std.mem.eql(u8, first, "local")) {
            var config = AppConfig{ .local = .{
                .renderMode = defaultRenderMode,
                .aiDifficulty = defaultAIDifficulty,
            } };

            while (iter.next()) |next| {
                if (std.mem.eql(u8, next, "--ai")) {
                    // get the value
                    if (iter.next()) |diff| {
                        config.local.aiDifficulty = try Ai.Difficulty.fromString(diff);
                    }
                } else if (std.mem.eql(u8, next, "--gui")) {
                    config.local.renderMode = .gui;
                }
            }

            return config;
        } else {
            std.debug.panic("unknown game type {s}\n", .{first});
            return error.UnknownGameType;
        }
    }
    debug.print("No argument was provided!\n", .{});
    debug.print(helpMessage, .{});
    return error.InvalidArgs;
}

fn testMakeArgs(allocator: Allocator, values: []const []const u8) ![][]u8 {
    const strings = try allocator.alloc([]u8, values.len);

    for (values, 0..) |value, i| {
        strings[i] = try allocator.dupe(u8, value);
    }

    return strings;
}
fn testFreeArgs(allocator: Allocator, args: [][]u8) void {
    for (args) |string| {
        allocator.free(string);
    }

    allocator.free(args);
}

test "parseConfig remote new" {
    const args = try testMakeArgs(testing.allocator, &.{
        "remote",
        "new",
        "--ai",
        "easy",
        "--host",
        "192.168.0.1",
        "--port",
        "1234",
    });
    defer testFreeArgs(testing.allocator, args);

    const config = try parseConfig(
        testing.allocator,
        args,
    );

    try testing.expectEqualDeep(AppConfig{
        .remoteNew = .{
            .aiDifficulty = .easy,
            .host = "192.168.0.1",
            .port = 1234,
        },
    }, config);
}

test "parseConfig remote join" {
    const args = try testMakeArgs(testing.allocator, &.{ "remote", "join", "abcd" });
    defer testFreeArgs(testing.allocator, args);

    const config = try parseConfig(
        testing.allocator,
        args,
    );

    try testing.expectEqualDeep(AppConfig{
        .remoteJoin = .{
            .code = "abcd",
            .host = default_host,
            .port = default_port,
        },
    }, config);
}

test "parseConfig local" {
    const args = try testMakeArgs(testing.allocator, &.{"local"});
    defer testFreeArgs(testing.allocator, args);

    const config = try parseConfig(
        testing.allocator,
        args,
    );

    try testing.expectEqualDeep(AppConfig{
        .local = .{
            .aiDifficulty = null,
        },
    }, config);
}

const MyIterator = struct {
    strings: [][]u8,
    index: usize = 0,

    // fn initMock(allocator: Allocator, values: []const []const u8) !MyIterator {
    //     const strings = try allocator.alloc([]u8, values.len);

    //     for (values, 0..) |value, i| {
    //         strings[i] = try allocator.dupe(u8, value);
    //     }

    //     return .{
    //         .strings = strings,
    //         .index = 0,
    //     };
    // }
    // fn deinitMock(self: *MyIterator, allocator: Allocator) void {
    //     for (self.strings) |string| {
    //         allocator.free(string);
    //     }

    //     allocator.free(self.strings);
    // }

    fn next(self: *MyIterator) ?[]u8 {
        const index = self.index;
        for (self.strings[index..]) |string| {
            self.index += 1;
            return string;
        }
        return null;
    }
    fn skip(self: *MyIterator) bool {
        if (self.index > self.strings.len - 1) {
            return false;
        }

        self.index += 1;
        return true;
    }
    fn reset(self: *MyIterator) void {
        self.index = 0;
    }
};

test MyIterator {
    // ugly codes here!!!
    var arr = std.ArrayList([]u8).init(testing.allocator);
    defer arr.deinit();
    const one = try testing.allocator.dupe(u8, "one");
    defer testing.allocator.free(one);
    try arr.append(one);
    const two = try testing.allocator.dupe(u8, "two");
    defer testing.allocator.free(two);
    try arr.append(two);

    var iter = MyIterator{ .strings = arr.items };

    try testing.expectEqualStrings("one", iter.next().?);
    try testing.expectEqualStrings("two", iter.next().?);
    try testing.expectEqual(null, iter.next());

    iter.reset();

    try testing.expectEqual(true, iter.skip());
    try testing.expectEqual(true, iter.skip());
    try testing.expectEqual(false, iter.skip());
}
