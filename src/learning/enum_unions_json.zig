const std = @import("std");
const json = std.json;
const ArrayList = std.ArrayList;

const Player = enum { X, O };

pub const Event = union(enum) {
    gameStart,
    gameFinished,
    makeMove: struct { player: Player, x: u32, y: u32 },
};

pub const EventFull = struct { event: Event, sid: u32, time: u32 };

pub const EventLog = []EventFull;

const testing = std.testing;

// seeing how serialization works
// its nice
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

    var out = ArrayList(u8).init(allocator);
    defer out.deinit();

    var eventLog = ArrayList(EventFull).init(allocator);
    defer eventLog.deinit();

    try eventLog.append(.{ .sid = 0, .time = 0, .event = .{ .gameStart = undefined } });
    try eventLog.append(.{ .sid = 1, .time = 20, .event = .{ .makeMove = .{ .player = .X, .x = 1, .y = 1 } } });

    try json.stringify(eventLog.items, .{}, out.writer());

    try testing.expectEqualStrings(
        \\[{"event":{"gameStart":{}},"sid":0,"time":0},{"event":{"makeMove":{"player":"X","x":1,"y":1}},"sid":1,"time":20}]
    , out.items);

    const parsed = try std.json.parseFromSlice(
        EventLog,
        allocator,
        out.items,
        .{},
    );
    defer parsed.deinit();

    try testing.expectEqualDeep(eventLog.items, parsed.value);
}
