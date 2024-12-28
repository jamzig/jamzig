const std = @import("std");
const testing = std.testing;

const stf = @import("stf.zig");
const sequoia = @import("sequoia.zig");
const state = @import("state.zig");
const jam_params = @import("jam_params.zig");

test "sequoia: State transition with sequoia-generated blocks" {
    // Initialize test environment
    const allocator = testing.allocator;

    // Create initial state using tiny test parameters
    var current_state = try state.JamState(jam_params.TINY_PARAMS).initGenesis(allocator);
    defer current_state.deinit(allocator);

    // Create block builder
    var builder = try sequoia.createTinyBlockBuilder(allocator, &current_state);
    defer builder.deinit();

    // Test multiple block transitions
    const num_blocks = 100;

    // Generate and process multiple blocks
    for (0..num_blocks) |i| {
        // Build next block
        var block = try builder.buildNextBlock();
        defer block.deinit(allocator);

        // Log block information for debugging
        std.debug.print("\nProcessing block {d}:\n", .{i});
        std.debug.print("  Slot: {d}\n", .{block.header.slot});
        std.debug.print("  Author: {d}\n", .{block.header.author_index});

        // Perform state transition
        var state_delta = try stf.stateTransition(jam_params.TINY_PARAMS, allocator, &current_state, &block);
        defer state_delta.deinit(allocator);

        // Verify basic state transition properties
        try testing.expect(state_delta.tau.? > current_state.tau.?);
        try testing.expect(state_delta.beta.?.blocks.items.len > 0);

        try current_state.merge(&state_delta, allocator);
    }
}
