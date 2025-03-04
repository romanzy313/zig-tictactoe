const std = @import("std");
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

        pub const Login = struct {
            id: [16]u8,
            name: [32]u8,
        };
        pub const GameCreate = struct {
            // there is an internal event for creating a game
            boardSize: u8,
            timeLimit: u64 = 0, // TODO: maybe implement this too?
        };
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
