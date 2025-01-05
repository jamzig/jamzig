const std = @import("std");
const state = @import("../state.zig");
const types = @import("../types.zig");

pub fn transitionServiceAccounts(
    allocator: std.mem.Allocator,
    current_delta: *const state.Delta,
    xtpreimages: types.PreimagesExtrinsic,
) !state.Delta {
    _ = allocator;
    _ = current_delta;
    _ = xtpreimages;
    // Transition δ with new preimages
    @panic("Not implemented");
}
