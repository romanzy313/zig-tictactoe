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
    pub const GameId = [16]u8;

    pub const Client2Server = union(enum(u8)) {
        Ping: void = 255,

        auth: Login = 0,
        gameJoin: GameId = 1,
        gameLeave: GameId = 2,
        gameCreate: GameCreate = 3,
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
            // there is an internal event for creating a game
            boardSize: u8,
            timeLimit: u64 = 0, // TODO: maybe implement this too?
        };

        pub fn serialize(self: Client2Server, writer: AnyWriter) !void {
            json.stringify(self, .{}, writer);
        }

        // pub fn deserialize(allocator: Allocator, reader: AnyReader) Client2Server {

        //     json.parseFromSlice(Client2Server, allocator, s: []const u8, options: ParseOptions)

        // }
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

test "serialization" {
    var buf: [100]u8 = undefined;
    var rw = std.io.fixedBufferStream(&buf);

    std.debug.print("why arent you testing", .{});
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
