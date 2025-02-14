const std = @import("std");
const game = @import("game.zig");
const Board = @import("Board.zig");
const Ai = @import("Ai.zig");
const UUID = @import("uuid").UUID;

// this is an envelope when data is being sent to the server
pub const EventWithEnvelope = struct {
    gameId: UUID, // mandatory, even in offline play... would be nice to implement ULID: Lexicographically sortable kind
    seqId: u32,
    timestamp: u64, // ideally should be a string thats json encodable
    data: GameEvent,
};

pub const GameEvent = union(enum) {
    gameCreated: GameCreated,
    playerJoined: PlayerJoined,
    moveMade: MoveMade,
    gameFinished: GameFinished, // this must be emitted by the authority

    // this non-serializeable event is used for sending errors over the network
    // and used by the app rendering to redraw error box as errors come in
    // TODO: scope all possible Errors into GameErrors, dont use anyerror
    __runtimeError: anyerror,

    // extern because of uuid
    pub const GameCreated = struct {
        gameId: UUID,
        boardSize: usize,
        timeLimit: u64 = 0, // TODO: maybe implement this too?
    };

    pub const PlayerJoined = struct {
        playerId: game.AnyPlayerId, // i guess AI's also will need id then?
        // name: [30:0]u8, // enforce max size, zero terminated. This should be persistent in the db and not stored here
        side: game.PlayerSide,
    };
    pub const MoveMade = struct {
        side: game.PlayerSide,
        position: Board.CellPosition,
    };
    pub const GameFinished = struct {
        winner: game.GameWinner,
    };
};
