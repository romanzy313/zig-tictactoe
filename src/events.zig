const std = @import("std");
const game = @import("game.zig");
const Board = @import("Board.zig");
const Ai = @import("Ai.zig");
const UUID = @import("uuid").UUID;

// this is an envelope when data is being sent to the server
pub const EventEnvelope = struct {
    game_id: UUID,
    seq_id: u32,
    timestamp: u64,
    event: Event,

    pub fn init(gameId: UUID, seqId: u32, timestamp: u64, data: Event) EventEnvelope {
        return .{
            .gameId = gameId,
            .seqId = seqId,
            .timestamp = timestamp,
            .data = data,
        };
    }

    // toBin and fromBin must be implemented on this
};

pub const Event = union(enum) {
    gameCreated: GameCreated,
    playerJoined: PlayerJoined,
    moveMade: MoveMade,
    gameFinished: GameFinished, // this must be emitted by the authority

    // this non-serializeable event is used for sending errors over the network
    // and used by the app rendering to redraw error box as errors come in
    // TODO: scope all possible Errors into GameErrors, dont use anyerror
    __runtimeError: anyerror,

    pub const GameCreated = struct {
        gameId: UUID,
        boardSize: usize,
        timeLimit: u64 = 0, // TODO: maybe implement this too?
    };

    pub const PlayerJoined = struct {
        playerId: game.AnyPlayerId, // Ai is part of this
        // name: [30:0]u8, // enforce max size, zero terminated. This should be persistent in the db and not stored here
        side: game.PlayerSide,
    };
    pub const MoveMade = struct {
        side: game.PlayerSide,
        position: Board.CellPosition,
    };
    pub const GameFinished = struct {
        outcome: game.GameOutcome,
    };
};
