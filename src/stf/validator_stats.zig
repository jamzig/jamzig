const std = @import("std");

const types = @import("../types.zig");
const state = @import("../state.zig");

const Params = @import("../jam_params.zig").Params;
const StateTransition = @import("../state_delta.zig").StateTransition;

const trace = @import("../tracing.zig").scoped(.stf);

pub const Error = error{};

pub fn transition(
    comptime params: Params,
    stx: *StateTransition(params),
    new_block: *const types.Block,
) !void {
    const span = trace.span(.transition_validator_stats);
    defer span.deinit();
    span.debug("Starting validator_stats transition", .{});

    var pi = try stx.ensureT(state.Pi, .pi_prime);

    if (stx.time.isNewEpoch()) {
        try pi.transitionToNextEpoch();
    }

    var stats = try pi.getValidatorStats(new_block.header.author_index);
    stats.blocks_produced += 1;
    stats.tickets_introduced += @intCast(new_block.extrinsic.tickets.data.len);
}
