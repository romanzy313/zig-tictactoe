const std = @import("std");
const Board = @import("board.zig").Board;
const json = std.json;
const ArrayList = std.ArrayList;

pub const Event = union(enum) {
    gameStart: struct {},
    gameFinished: struct {},
    makeMove: struct { player: Board.Player, x: u32, y: u32 },
};

pub const EventFull = struct { event: Event, sid: u32, time: u32 };

pub const EventLog = []EventFull;

// tests

const testing = std.testing;

// seeing how serialization works
// its ncie
test "json serialize 1" {
    const allocator = testing.allocator;

    var string = ArrayList(u8).init(allocator);
    defer string.deinit();

    const moveEvent: EventFull = .{ .sid = 0, .time = 0, .event = .{ .makeMove = .{ .player = .X, .x = 1, .y = 1 } } };
    try json.stringify(moveEvent, .{}, string.writer());

    try testing.expectEqualStrings(
        \\{"event":{"makeMove":{"player":"X","x":1,"y":1}},"sid":0,"time":0}
    , string.items);
}

test "json serialize and decerialize json array" {
    const allocator = testing.allocator;

    var string = ArrayList(u8).init(allocator);
    defer string.deinit();

    var eventLog = ArrayList(EventFull).init(allocator);
    defer eventLog.deinit();

    try eventLog.append(.{ .sid = 0, .time = 0, .event = .{ .gameStart = .{} } });
    try eventLog.append(.{ .sid = 1, .time = 20, .event = .{ .makeMove = .{ .player = .X, .x = 1, .y = 1 } } });

    try json.stringify(eventLog.items, .{}, string.writer());

    try testing.expectEqualStrings(
        \\[{"event":{"gameStart":{}},"sid":0,"time":0},{"event":{"makeMove":{"player":"X","x":1,"y":1}},"sid":1,"time":20}]
    , string.items);

    const parsed = try std.json.parseFromSlice(
        EventLog,
        allocator,
        string.items,
        .{},
    );
    defer parsed.deinit();

    try testing.expectEqualDeep(eventLog.items, parsed.value);
}
