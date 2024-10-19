const std = @import("std");
const Allocator = std.mem.Allocator;

const game = @import("game.zig");
const Ai = @import("ai.zig").Ai;

pub const LocalWithAi = struct {
    state: *game.State,
    ai: Ai,

    pub fn init(state: *game.State, ai: Ai, playerStarts: bool) LocalWithAi {
        // const state = game.State.init(allocator, 3); // where does this 3 parameter go?

        if (!playerStarts) {
            const move = ai.getMove(state);
            _ = state.makeMove(move) catch @panic("will never happen: always moves available");
        }

        return .{
            .state = state,
            .ai = ai,
        };
    }

    // returns true if more moves are pending
    pub fn submitMove(self: LocalWithAi, move: game.CellPosition) !bool {
        const status = try self.state.makeMove(move);
        if (!status.isPlaying()) {
            return false; // game is finished
        }
        const aiMove = self.ai.getMove(self.state);

        const status2 = try self.state.makeMove(aiMove);

        return status2.isPlaying();
    }
};

pub const LocalMultiplayer = struct {
    currentPlayer: game.Player,
    state: *game.State,

    pub fn init(state: *game.State, player: game.Player) LocalMultiplayer {
        // const state = game.State.init(allocator, 3); // where does this 3 parameter go?

        return .{
            .state = state,
            .currentPlayer = player,
        };
    }

    // returns true if more moves are pending
    pub fn submitMove(self: LocalMultiplayer, move: game.CellPosition) !bool {
        const status = try self.state.makeMove(move);
        return status.isPlaying();
    }
};

// TODO
// this one still should hold the state! as it will be synced with the server
// and updated optimistically! (again, for learning experience)
pub const Remote = struct {
    url: []const u8,

    pub fn init(url: []const u8) Remote {
        return .{
            .url = url,
        };
    }
};

pub const Request = union(enum) {
    makeMove: game.CellPosition,
};

pub const Response = union(enum) {
    stateUpdate: game.State,
    // err: []const u8, // TODO: typed errors as string
};

pub const UniversalServer = struct {
    state: *game.State,
    ai: ?Ai,

    pub fn init(state: *game.State, ai: ?Ai, playerStarts: bool) UniversalServer {
        // const state = game.State.init(allocator, 3); // where does this 3 parameter go?
        if (ai != null and !playerStarts) {
            const move = ai.?.getMove(state);
            _ = state.makeMove(move) catch @panic("will never happen: always moves available");
        }

        return .{
            .state = state,
            .ai = ai,
        };
    }

    // hmm?
    pub fn stateCopy(self: UniversalServer) game.State {
        return self.state.*;
    }

    pub fn handleRequest(self: UniversalServer, req: Request) !Response {
        // if AI is enabled, the move must be delegated to the AI...
        // that must be done via networking though by the server!

        return switch (req) {
            .makeMove => |pos| {
                const status = try self.state.makeMove(pos);
                if (!status.isPlaying()) {
                    return .{
                        .stateUpdate = self.state.*,
                    };
                }
                if (self.ai != null) {
                    const aiMove = self.ai.?.getMove(self.state);

                    _ = try self.state.makeMove(aiMove);
                }

                return .{
                    .stateUpdate = self.state.*,
                };
            },
            // else => return error.NotImplemented,
        };
    }
};
