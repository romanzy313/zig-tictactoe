const std = @import("std");
const Allocator = std.mem.Allocator;
const AnyWriter = std.io.AnyWriter;
const AnyReader = std.io.AnyReader;
const json = std.json;
const testing = std.testing;

const UUID = @import("uuid").UUID;
const Event = @import("events.zig").Event;

// a discriminated union of event types, attached with the data.

pub const Proto = struct {
    // TODO: this also need serialise/deserisize functionality
    // zig is really bad at this...

    pub const GameId = [16]u8;

    pub const Client2Server = union(enum(u8)) {
        Ping: void = 255,

        auth: Login = 0,
        gameJoin: GameId = 1,
        gameLeave: GameId = 2,
        gameCreate: GameCreate = 3,
        // trying to pinpint leak location
        gameSubmitEvent: Event = 4,

        // unfortunately the serialization cannot be simplied by declaring this as a
        // "packed struct"
        // error: packed structs cannot contain fields of type '[16]u8'
        // this is because of array endianess...
        // see https://github.com/ziglang/zig/issues/10113#issuecomment-1036713233
        pub const Login = struct {
            id: [16]u8,
            name: [32]u8,

            // this works without needed an allocator, like in the case of json
            // but what if the original memory is cleaned up?
            // what if the original written is no longer in scope?
            // do i need to dupe everything in this case?
            // this is where zigs memory management gets iffy...
            // need to know who OWNS memory for cleanup and also for long-living references
            // if these values are passed along to some long running zig storage (like a HashMap)
            // then after the incoming message goes out of scope, these values will become trash
            // and then its confusing where the bad memory came from
            pub fn serialize(self: Login, writer: AnyWriter) !void {
                _ = try writer.write(&self.id);
                _ = try writer.write(&self.name);
            }
            pub fn deserialize(reader: AnyReader) !Login {
                var login = Login{ .id = undefined, .name = undefined };
                _ = try reader.read(&login.id);
                _ = try reader.read(&login.name);
                return login;
            }
        };
        pub const GameCreate = struct {
            board_size: u8,
            time_limit: u64 = 0, // TODO: maybe implement this too?

            pub fn serialize(self: GameCreate, writer: AnyWriter) !void {
                try writer.writeByte(self.board_size);
            }
            pub fn deserialize(reader: AnyReader) !GameCreate {
                var game_create = GameCreate{ .board_size = undefined };
                game_create.board_size = try reader.readByte(&game_create);
                return game_create;
            }
        };

        pub fn serialize(self: Client2Server, writer: AnyWriter) !void {
            try json.stringify(self, .{}, writer);
        }

        pub fn deserialize(allocator: Allocator, reader: AnyReader) !Client2Server {
            var json_reader = json.reader(allocator, reader);
            defer json_reader.deinit();

            const res = try json.parseFromTokenSource(Client2Server, allocator, &json_reader, .{ .allocate = .alloc_always });
            defer res.deinit(); // this is safe as all values comes from orignal buffer?

            return res.value;
        }
    };

    pub const Server2Client = union(enum(u8)) {
        Pong: void = 255,

        authOk: void = 0,
        authErr: AuthErr = 1,
        gameJoinOk: GameJoinOk = 2,
        gameJoinErr: GenericError = 3,
        // TODO: gameLeave events
        gameLeaveOk: GameId = 4,
        gameLeaveErr: GenericError = 5,

        // we just ack okay with game id.
        // later on, the client will recieve the gameCreatedEvent
        gameCreateOk: GameCreateOk = 6,
        gameCreateErr: GenericError = 7,

        gameEvent: GameEvent = 8,

        pub const AuthErr = struct {
            reason: [7]u8, // TODO
        };
        pub const GameJoinOk = struct {
            game_id: GameId,
            // return the list of events of the existing game
            // this will include the Event.GameCreated always!
            events: []Event,
        };
        pub const GameCreateOk = struct {
            game_id: GameId,
            initial_event: Event.GameCreated,
        };
        pub const GameEvent = struct {
            game_id: GameId,
            seq_id: u32, // in order for client to ignore duplicates
            event: Event,
        };

        pub const GenericError = struct {
            len: u8,
            msg: []u8,
        };
    };
};

test "serialization manual" {
    var buf: [100]u8 = undefined;
    var rw = std.io.fixedBufferStream(&buf);

    const og = Proto.Client2Server.Login{
        .id = UUID.initFromNumber(10).bytes,
        .name = [_]u8{'a'} ** 32,
    };

    try og.serialize(rw.writer().any());
    // std.debug.print("serialized value is {s}\n", .{rw.getWritten()});

    try rw.seekTo(0);
    const new = try Proto.Client2Server.Login.deserialize(rw.reader().any());
    try testing.expectEqualDeep(og, new);
}

test "serialization as json" {
    var buf: [95]u8 = undefined;
    var rw = std.io.fixedBufferStream(&buf);

    const og = Proto.Client2Server{ .auth = .{
        .id = UUID.initFromNumber(10).bytes,
        .name = [_]u8{'a'} ** 32,
    } };

    try og.serialize(rw.writer().any());
    std.debug.print("serialized value is {s}\n", .{rw.getWritten()});

    try rw.seekTo(0);
    // this wont fail if exactly the full buffer contains the value
    // this will be the case when values are separated by newlines
    const new = try Proto.Client2Server.deserialize(testing.allocator, rw.reader().any());

    try testing.expectEqualDeep(og, new);
}

// another idea is to define an RPC
// but this must be tightly integrated into a global table for all events
// as union(enum) kind of needs to be reconstructed on both the caller and callee
//
// automatic id generation to make it simple to do blocking requests.
pub fn RPC(req_id: comptime_int, Req: type, Res: type, Err: type) type {
    _ = req_id;

    return struct {
        Req: Req,
        Res: Res,
        Err: Err,

        const Self = @This();
    };
}
