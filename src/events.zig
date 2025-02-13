const std = @import("std");
const game = @import("game.zig");
const Board = @import("Board.zig");
const Ai = @import("Ai.zig");
const UUID = @import("uuid").UUID;

pub const Event = union(enum) {
    startGame: StartGameEvent,
    makeMove: MakeMoveEvent,
};

// can try different way of modeling it
// gameStart just defines the board size
// then there must be an event PlayerJoined, and each player must choose a side. AI is also considered a player
// the player is encoded as an id

// when serializing the envelope it should be important to flatten this as much as possible
pub const EventWithEnvelope = struct {
    eventId: UUID, // globally unique event id
    timestamp: u64, // ideally should be a string thats json encodable
    detail: struct {
        metadata: struct {
            gameId: UUID, // used for aggregation
            seqId: u32,
        },
        data: Event2,
    },
};

pub const Event2 = union(enum) {
    gameCreated: GameCreatedEvent2,
    playerJoined: PlayerJoinedEvent2,
    aiJoined: PlayerJoinedEvent2,
    moveMade: MoveMadeEvent2,
    gameFinished: GameFinishedEvent2, // this must be emitted by the authority
};

pub const GameCreatedEvent2 = struct {
    boardSize: usize,
    timeLimit: ?u64, // TODO: maybe implement this too?
};

pub const PlayerJoinedEvent2 = struct {
    playerId: UUID,
    side: game.PlayerSide,
};

pub const AIJoinedEvent2 = struct {
    difficulty: Ai.Difficulty,
    side: game.PlayerSide,
};

pub const MoveMadeEvent2 = struct {
    side: game.PlayerSide,
    position: Board.CellPosition,
};

pub const GameFinishedEvent2 = struct {
    playerId: []const u8,
    winner: struct {
        .stalemate,
        .x,
        .y,
    },
};

pub const StartGameEvent = union(game.GameMode) {
    withAi: struct {
        boardSize: usize,
        playerSide: game.PlayerSide,
        aiDifficulty: Ai.Difficulty,
    },
    multiplayer: struct {
        boardSize: usize,
        playerSide: game.PlayerSide, // player can choose to start as O
    },

    pub fn boardSize(self: StartGameEvent) usize {
        return switch (self) {
            inline else => |*case| return case.boardSize,
        };
    }
    pub fn playerSide(self: StartGameEvent) game.PlayerSide {
        return switch (self) {
            inline else => |*case| return case.playerSize,
        };
    }
    pub fn gameMode(self: StartGameEvent) game.GameMode {
        return switch (self) {
            .withAi => game.GameMode.withAi,
            .multiplayer => game.GameMode.multiplayer,
        };
    }
};

pub const MakeMoveEvent = struct {
    position: Board.CellPosition,
};
