const std = @import("std");

// broken example for now
const GameEventWithEnvelope = struct {};
const UUID = struct {};
// how can we convert the events into envelopes?
const TestIntegrationMultiplexed = struct {
    // this needs to hold a map of these events? as envelope is needed to properly write and serialize them
    // also the envelope is sent across the wire
    values: std.BoundedArray(GameEventWithEnvelope, 10),

    pub fn init() TestIntegrationMultiplexed {
        return .{
            .values = std.BoundedArray(GameEventWithEnvelope, 10){},
        };
    }

    pub fn newWrapper(self: *TestIntegrationMultiplexed, gameId: UUID) EnvelopeWrapper {
        return .{
            .parent = self,
            .gameId = gameId,
        };
    }

    const EnvelopeWrapper = struct {
        parent: *TestIntegrationMultiplexed,
        gameId: UUID,
        seqId: usize = 0, // this is not doing well, as game starts with event 0. maybe it starts with event 1, in order to signify nullity of the situation

        pub fn publishEvent(self: *EnvelopeWrapper, ev: GameEvent) void {
            const timestamp: u64 = @intCast(std.time.milliTimestamp());
            self.parent.publishEnvelope(self.parent, GameEventWithEnvelope{
                .gameId = self.gameId,
                .seqId = self.seqId,
                .timestamp = timestamp,
                .event = ev,
            });
            self.seqId += 1;
        }
    };

    pub fn publishEnvelope(self: *TestIntegrationMultiplexed, ev: GameEventWithEnvelope) void {
        // networking here
        self.values.append(ev) catch @panic("event envelope overflow");
    }
};
