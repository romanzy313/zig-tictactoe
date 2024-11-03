// taken from https://github.com/dmgk/zig-uuid/blob/master/uuid.zig

// Fast allocation-free v4 UUIDs.
// Inspired by the Go implementation at github.com/skeeto/uuid

const std = @import("std");
const crypto = std.crypto;
const fmt = std.fmt;
const json = std.json;
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const Error = error{InvalidUUID};

pub const UUID = struct {
    bytes: [16]u8,

    pub fn init() UUID {
        var uuid = UUID{ .bytes = undefined };

        crypto.random.bytes(&uuid.bytes);
        // Version 4
        uuid.bytes[6] = (uuid.bytes[6] & 0x0f) | 0x40;
        // Variant 1
        uuid.bytes[8] = (uuid.bytes[8] & 0x3f) | 0x80;
        return uuid;
    }

    fn to_string(self: UUID, slice: []u8) void {
        var string: [36]u8 = format_uuid(self);
        @memcpy(slice, &string);
    }

    // FIXME: allow this exposed for simplicity?
    pub fn format_uuid(self: UUID) [36]u8 {
        var buf: [36]u8 = undefined;
        buf[8] = '-';
        buf[13] = '-';
        buf[18] = '-';
        buf[23] = '-';
        inline for (encoded_pos, 0..) |i, j| {
            buf[i + 0] = hex[self.bytes[j] >> 4];
            buf[i + 1] = hex[self.bytes[j] & 0x0f];
        }
        return buf;
    }

    // Indices in the UUID string representation for each byte.
    const encoded_pos = [16]u8{ 0, 2, 4, 6, 9, 11, 14, 16, 19, 21, 24, 26, 28, 30, 32, 34 };

    // Hex
    const hex = "0123456789abcdef";

    // Hex to nibble mapping.
    const hex_to_nibble = [256]u8{
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    };

    pub fn format(
        self: UUID,
        comptime layout: []const u8,
        options: fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options; // currently unused

        if (layout.len != 0 and layout[0] != 's')
            @compileError("Unsupported format specifier for UUID type: '" ++ layout ++ "'.");

        const buf = format_uuid(self);

        try fmt.format(writer, "{s}", .{buf});
    }

    pub fn parse(buf: []const u8) Error!UUID {
        var uuid = UUID{ .bytes = undefined };

        if (buf.len != 36 or buf[8] != '-' or buf[13] != '-' or buf[18] != '-' or buf[23] != '-')
            return Error.InvalidUUID;

        inline for (encoded_pos, 0..) |i, j| {
            const hi = hex_to_nibble[buf[i + 0]];
            const lo = hex_to_nibble[buf[i + 1]];
            if (hi == 0xff or lo == 0xff) {
                return Error.InvalidUUID;
            }
            uuid.bytes[j] = hi << 4 | lo;
        }

        return uuid;
    }

    pub fn jsonStringify(self: UUID, out: anytype) !void {
        return out.print("\"{s}\"", .{self.format_uuid()});
    }

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        _: json.ParseOptions,
    ) !UUID {
        switch (try source.nextAlloc(allocator, .alloc_if_needed)) {
            .string, .allocated_string => |value| {
                return parse(value) catch error.InvalidCharacter;
            },
            else => return error.UnexpectedToken,
        }
    }
};

// source https://www.aolium.com/karlseguin/46252c5b-587a-c419-be96-a0ccc2f11de4
// source https://www.openmymind.net/Custom-String-Formatting-And-JSON-in-Zig/

// Zero UUID
pub const zero: UUID = .{ .bytes = .{0} ** 16 };

// Convenience function to return a new v4 UUID.
pub fn newV4() UUID {
    return UUID.init();
}

test "parse and format" {
    const uuids = [_][]const u8{
        "d0cd8041-0504-40cb-ac8e-d05960d205ec",
        "3df6f0e4-f9b1-4e34-ad70-33206069b995",
        "f982cf56-c4ab-4229-b23c-d17377d000be",
        "6b9f53be-cf46-40e8-8627-6b60dc33def8",
        "c282ec76-ac18-4d4a-8a29-3b94f5c74813",
        "00000000-0000-0000-0000-000000000000",
    };

    for (uuids) |uuid| {
        try testing.expectFmt(uuid, "{}", .{try UUID.parse(uuid)});
    }
}

test "invalid UUID" {
    const uuids = [_][]const u8{
        "3df6f0e4-f9b1-4e34-ad70-33206069b99", // too short
        "3df6f0e4-f9b1-4e34-ad70-33206069b9912", // too long
        "3df6f0e4-f9b1-4e34-ad70_33206069b9912", // missing or invalid group separator
        "zdf6f0e4-f9b1-4e34-ad70-33206069b995", // invalid character
    };

    for (uuids) |uuid| {
        try testing.expectError(Error.InvalidUUID, UUID.parse(uuid));
    }
}

test "check to_string works" {
    const uuid1 = UUID.init();

    var string1: [36]u8 = undefined;
    var string2: [36]u8 = undefined;

    uuid1.to_string(&string1);
    uuid1.to_string(&string2);

    std.debug.print("\nUUID {s} \n", .{uuid1});
    std.debug.print("\nFirst  call to_string {s} \n", .{string1});
    std.debug.print("Second call to_string {s} \n", .{string2});
    try testing.expectEqual(string1, string2);
}

test "jsonStringify" {
    const uuid = UUID{
        .bytes = [_]u8{ 0x12, 0x34, 0x56, 0x78, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    };
    const T = struct { id: UUID };
    const res = try json.stringifyAlloc(testing.allocator, T{
        .id = uuid,
    }, .{});
    defer testing.allocator.free(res);
    try testing.expectEqualStrings("{\"id\":\"12345678-0000-0000-0000-000000000000\"}", res);

    const res2 = try json.stringifyAlloc(testing.allocator, uuid, .{});
    defer testing.allocator.free(res2);
    try testing.expectEqualStrings("\"12345678-0000-0000-0000-000000000000\"", res2);
}

test "jsonParse" {
    const T = struct { id: UUID };

    const res = try json.parseFromSlice(
        T,
        testing.allocator,
        "{\"id\": \"12345678-0000-0000-0000-000000000000\"}",
        .{},
    );
    defer res.deinit();
    try testing.expectEqual([_]u8{ 0x12, 0x34, 0x56, 0x78, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, res.value.id.bytes);
}

test "bad jsonParse" {
    const T = struct { id: UUID };

    try testing.expectError(error.UnexpectedToken, json.parseFromSlice(
        T,
        testing.allocator,
        "{\"id\": 123123}",
        .{},
    ));
}
