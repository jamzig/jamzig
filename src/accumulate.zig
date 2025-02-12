const std = @import("std");
const types = @import("types.zig");
const state = @import("state.zig");
const Params = @import("jam_params.zig").Params;

pub fn processAccumulateReports(
    comptime params: Params,
    allocator: std.mem.Allocator,
    reports: []types.WorkReport,
    time_slot: types.TimeSlot,
    delta: *state.Delta,
    theta: *state.Theta(params.epoch_length),
    chi: *state.Chi,
    xi: *state.Xi(params.epoch_length),
) !types.AccumulateRoot {
    _ = allocator;
    _ = reports;
    _ = time_slot;
    _ = delta;
    _ = theta;
    _ = chi;
    _ = xi;

    return [_]u8{0} ** 32;
}
