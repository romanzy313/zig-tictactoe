const std = @import("std");
const AnyWriter = std.io.AnyWriter;
const AnyReader = std.io.AnyReader;
const UUID = @import("uuid").UUID;

const game = @import("game.zig");
const Ai = @import("Ai.zig");
const Board = @import("Board.zig");

const testing = std.testing;

// this is an envelope when data is being sent to the server
pub const EventEnvelope = struct {
    game_id: UUID,
    seq_id: u32,
    timestamp: u64,
    event: Event,

    pub fn init(game_id: UUID, seq_id: u32, timestamp: u64, event: Event) EventEnvelope {
        return .{
            .game_id = game_id,
            .seq_id = seq_id,
            .timestamp = timestamp,
            .event = event,
        };
    }

    // toBin and fromBin must be implemented on this

    // ignore the game_id here when encoding
    // still provide it when decoding?
    // but instead im just gonna do json for this whole object
    // with static
    pub fn toBin(self: EventEnvelope, writer: AnyWriter) !void {
        try std.json.stringify(self, .{}, writer);
        try writer.writeByte('\n'); // ugly add a delimiter

        // to not write __runtimeError
        // switch (self.event) {
        //     .__runtimeError => _ = try writer.write("__runtimeError\n"),
        //     else => {
        //         try std.json.stringify(self, .{}, writer);
        //         try writer.writeByte('\n'); // ugly add a delimiter
        //     },
        // }
    }

    pub fn fromBin(reader: AnyReader) !EventEnvelope {
        const max_size = 200; //ughhh
        var buff: [max_size]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buff);
        try reader.streamUntilDelimiter(fbs.writer(), '\n', max_size);

        // this is really ugly though
        var buff2: [200]u8 = undefined;
        var alloc = std.heap.FixedBufferAllocator.init(&buff2);

        const res = try std.json.parseFromSlice(EventEnvelope, alloc.allocator(), fbs.getWritten(), .{
            .allocate = .alloc_if_needed,
        });
        defer res.deinit();

        return res.value;
    }
};

test EventEnvelope {
    var buff: [200]u8 = undefined;
    var rw = std.io.fixedBufferStream(&buff);

    const og = EventEnvelope.init(
        UUID.initFromNumber(9),
        10,
        30,
        .{ .moveMade = .{
            .side = .x,
            .position = .{ .x = 3, .y = 3 },
        } },
    );

    try og.toBin(rw.writer().any());

    // std.debug.print("encoded value: {s}\n", .{rw.getWritten()});

    try rw.seekTo(0);

    const res = try EventEnvelope.fromBin(rw.reader().any());

    try testing.expectEqual(og, res);
}

pub const Event = union(enum) {
    gameCreated: GameCreated,
    playerJoined: PlayerJoined,
    moveMade: MoveMade,
    gameFinished: GameFinished, // this must be emitted by the authority

    // this non-serializeable event is used for sending errors over the network
    // and used by the app rendering to redraw error box as errors come in
    // TODO: scope all possible Errors into GameErrors, dont use anyerror
    // __runtimeError: RuntimeEncodedError,
    __runtimeError: RuntimeError, // no error reporting yet

    pub const GameCreated = struct {
        gameId: UUID,
        boardSize: u8,
        timeLimit: u64 = 0, // TODO: maybe implement this too?

        pub fn toBin(self: @This(), writer: AnyWriter) !void {
            try self.gameId.write(writer);
            try writer.writeInt(u8, self.boardSize, .big);
        }
        pub fn fromBin(reader: AnyReader) !@This() {
            return .{
                .gameId = try UUID.read(reader),
                .boardSize = try reader.readInt(u8, .big),
            };
        }

        test "to/from Bin" {
            var buff: [100]u8 = undefined;
            var rw = std.io.fixedBufferStream(&buff);

            const og = GameCreated{
                .gameId = UUID.initFromNumber(9),
                .boardSize = 3,
            };

            try og.toBin(rw.writer().any());

            try rw.seekTo(0);

            const res = try GameCreated.fromBin(rw.reader().any());

            try testing.expectEqual(og, res);
        }
    };

    pub const PlayerJoined = struct {
        playerId: game.AnyPlayerId, // Ai is part of this
        // name: [30:0]u8, // enforce max size, zero terminated. This should be persistent in the db and not stored here
        side: game.PlayerSide,

        // pub fn toBin(self: @This(), writer: AnyWriter) void {}
        // pub fn fromBin(reader: AnyReader) @This() {}

        pub fn toBin(self: PlayerJoined, writer: AnyWriter) !void {
            // json wrap here?
            try std.json.stringify(self, .{}, writer);

            try writer.writeByte('\n'); // ugly add a delimiter
        }
        pub fn fromBin(reader: AnyReader) !PlayerJoined {
            const buff_size = 100;
            // allocator needed...
            var buff: [buff_size]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&buff);
            try reader.streamUntilDelimiter(fbs.writer(), '\n', buff_size);

            // this is really ugly though
            var buff2: [200]u8 = undefined;
            var alloc = std.heap.FixedBufferAllocator.init(&buff2);
            const res = try std.json.parseFromSlice(PlayerJoined, alloc.allocator(), fbs.getWritten(), .{
                .allocate = .alloc_if_needed,
            });
            defer res.deinit();

            return res.value;
        }

        test "to/from Bin" {
            var buff: [100]u8 = undefined;
            var rw = std.io.fixedBufferStream(&buff);

            const og = PlayerJoined{
                .playerId = .{ .human = UUID.initFromNumber(9) },
                .side = .x,
            };

            try og.toBin(rw.writer().any());

            // std.debug.print("encoded value: {s}\n", .{rw.getWritten()});

            try rw.seekTo(0);

            const res = try PlayerJoined.fromBin(rw.reader().any());

            try testing.expectEqual(og, res);
        }
    };
    pub const MoveMade = struct {
        side: game.PlayerSide,
        position: Board.CellPosition,
    };
    pub const GameFinished = struct {
        outcome: game.GameOutcome,
    };

    pub const RuntimeError = enum {
        BROKEN_IMPL,

        GameFinished,
        BadEvent,
        PlayerOfThisSideAleadyJoined,
        CantPlayYet,
        WrongSide,
        InvalidPosition,
        CannotSelectAlreadySelected,

        pub fn fromError(err: anyerror) RuntimeError {
            return switch (err) {
                error.CannotSelectAlreadySelected => .CannotSelectAlreadySelected,
                error.CantPlayYet => .CantPlayYet,
                error.PlayerOfThisSideAleadyJoined => .PlayerOfThisSideAleadyJoined,
                error.WrongSide => .WrongSide,
                else => .BROKEN_IMPL,
            };
        }
        pub fn toStringz(self: RuntimeError) [*:0]const u8 {
            return @tagName(self);
        }
    };
};
