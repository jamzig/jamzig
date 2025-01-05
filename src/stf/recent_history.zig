const std = @import("std");
const state_d = @import("../state_delta.zig");
const StateTransition = state_d.StateTransition;
const Params = @import("../jam_params.zig").Params;
const types = @import("../types.zig");
const tracing = @import("../tracing.zig");
const trace = tracing.scoped(.stf);

pub fn transitionRecentHistory(
    comptime params: Params,
    stx: *StateTransition(params),
    new_block: *const types.Block,
) !void {
    const span = trace.span(.transition_recent_history);
    defer span.deinit();

    var beta_prime = try stx.ensure(.beta_prime);

    span.debug("Starting recent history transition", .{});
    span.trace("Current beta block count: {d}", .{beta_prime.blocks.items.len});

    const RecentBlock = @import("../recent_blocks.zig").RecentBlock;
    // Transition β with information from the new block
    try beta_prime.import(try RecentBlock.fromBlock(params, stx.allocator, new_block));
}
