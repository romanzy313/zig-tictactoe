const std = @import("std");
const game = @import("game.zig");
const Board = @import("Board.zig");
const Ai = @import("Ai.zig");

pub const Event = union(enum) {
    startGame: StartGameEvent,
    makeMove: MakeMoveEvent,
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
    pub fn playerSize(self: StartGameEvent) game.PlayerSide {
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
