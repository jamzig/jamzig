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

    // Setup our seeded Rng
    const seed: [32]u8 = [_]u8{42} ** 32;
    var prng = std.Random.ChaCha.init(seed);
    var rng = prng.random();

    // Create genesis state
    const config = try sequoia.GenesisConfig(jam_params.TINY_PARAMS).buildWithRng(allocator, &rng);

    // Create block builder
    var builder = try sequoia.BlockBuilder(jam_params.TINY_PARAMS).init(allocator, config, &rng);
    defer builder.deinit();

    // Test multiple block transitions
    const num_blocks = 32;

    // Let's give access to the current state
    var current_state = &builder.state;

    // std.debug.print("Initial state: {s}\n", .{current_state});

    // Generate and process multiple blocks
    for (0..num_blocks) |_| {
        // Build next block
        var block = try builder.buildNextBlock();
        defer block.deinit(allocator);

        // Log block information for debugging
        sequoia.logging.printStateTransitionDebug(jam_params.TINY_PARAMS, current_state, &block);

        // Perform state transition
        var state_delta = try stf.stateTransition(jam_params.TINY_PARAMS, allocator, current_state, &block);
        defer state_delta.deinit(allocator);

        // Verify basic state transition properties
        try testing.expect(state_delta.tau.? > current_state.tau.?);
        try testing.expect(state_delta.beta.?.blocks.items.len > 0);

        try current_state.merge(&state_delta, allocator);
    }
}
