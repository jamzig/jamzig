const std = @import("std");
const state_d = @import("../state_delta.zig");
const StateTransition = state_d.StateTransition;
const Params = @import("../jam_params.zig").Params;
const types = @import("../types.zig");
const tracing = @import("../tracing.zig");
const trace = tracing.scoped(.stf);

pub fn transitionTime(
    comptime params: Params,
    stx: *StateTransition(params),
    header_slot: types.TimeSlot,
) !void {
    const span = trace.span(.transition_time);
    defer span.deinit();
    span.debug("Starting time transition", .{});

    const current_tau = try stx.ensure(.tau);
    if (header_slot <= current_tau.*) {
        span.err("Invalid slot: new slot {d} <= current tau {d}", .{ header_slot, current_tau });
        return error.bad_slot;
    }

    const tau_prime = try stx.ensure(.tau_prime);  
    tau_prime.* = header_slot;
}
