const std = @import("std");

const state = @import("../state.zig");
const types = @import("../types.zig");

pub const Error = error{
    invalid_preimage_extrinsic,
};

pub fn transition(
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
