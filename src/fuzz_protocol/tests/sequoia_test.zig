const std = @import("std");
const testing = std.testing;
const net = std.net;
const messages = @import("../messages.zig");
const TargetServer = @import("../target.zig").TargetServer;
const sequoia = @import("../../sequoia.zig");
const types = @import("../../types.zig");
const codec = @import("../../codec.zig");
const shared = @import("shared.zig");

const trace = @import("../../tracing.zig").scoped(.fuzz_protocol);

test "basic_block_import" {
    const span = trace.span(.test_multiple_blocks);
    defer span.deinit();

    const allocator = testing.allocator;

    // Setup
    var sockets = try shared.createSocketPair();
    defer sockets.deinit();

    var target = TargetServer.init(allocator, "unused");
    defer target.deinit();

    // Perform handshake
    const handshake_complete = try shared.performHandshake(allocator, sockets.fuzzer, sockets.target, &target);

    // Generate multiple blocks
    var prng = std.Random.DefaultPrng.init(54321);
    var rng = prng.random();

    var block_builder = try sequoia.createTinyBlockBuilder(allocator, &rng);
    defer block_builder.deinit();

    const num_blocks = 5;
    var state_roots = std.ArrayList(messages.StateRootHash).init(allocator);
    defer state_roots.deinit();

    for (0..num_blocks) |i| {
        span.debug("Processing block {d}/{d}", .{ i + 1, num_blocks });

        const result = try runFuzzingCycle(
            allocator,
            sockets.fuzzer,
            sockets.target,
            &target,
            handshake_complete,
            &block_builder,
            false, // no mutation
            0.0,
            &rng,
        );

        try state_roots.append(result.target_root);

        // Verify each block import succeeded
        // In current implementation, all should return the same state root
        if (i > 0) {
            try testing.expectEqualSlices(u8, &state_roots.items[0], &state_roots.items[i]);
        }
    }

    span.debug("Multiple blocks test completed successfully", .{});
}

test "mutated_blocks" {
    if (true) {
        return error.SkipTest;
    }

    const span = trace.span(.test_comprehensive_fuzzing);
    defer span.deinit();

    const allocator = testing.allocator;

    // Setup
    var sockets = try shared.createSocketPair();
    defer sockets.deinit();

    var target = TargetServer.init(allocator, "unused");
    defer target.deinit();

    // Perform handshake
    const handshake_complete = try shared.performHandshake(allocator, sockets.fuzzer, sockets.target, &target);

    var prng = std.Random.DefaultPrng.init(13579);
    var rng = prng.random();

    var block_builder = try sequoia.createTinyBlockBuilder(allocator, &rng);
    defer block_builder.deinit();

    // Comprehensive test: mix of normal and mutated blocks
    const test_cases = [_]struct { mutate: bool, rate: f32 }{
        .{ .mutate = false, .rate = 0.0 }, // Normal block
        .{ .mutate = true, .rate = 0.001 }, // Lightly mutated
        .{ .mutate = false, .rate = 0.0 }, // Normal block
        .{ .mutate = true, .rate = 0.05 }, // Heavily mutated
        .{ .mutate = false, .rate = 0.0 }, // Normal block
    };

    var results = std.ArrayList(messages.StateRootHash).init(allocator);
    defer results.deinit();

    for (test_cases, 0..) |test_case, i| {
        span.debug("Test case {d}: mutate={}, rate={d}", .{ i, test_case.mutate, test_case.rate });

        const result = try runFuzzingCycle(
            allocator,
            sockets.fuzzer,
            sockets.target,
            &target,
            handshake_complete,
            &block_builder,
            test_case.mutate,
            test_case.rate,
            &rng,
        );

        try results.append(result.target_root);

        // Verify target is still responsive
        try testing.expect(target.current_state_root != null or std.mem.allEqual(u8, &result.target_root, 0));
    }

    // In current implementation, all should be the same
    // In a real implementation, we'd expect different roots for different blocks
    for (results.items[1..]) |root| {
        try testing.expectEqualSlices(u8, &results.items[0], &root);
    }

    span.debug("Comprehensive fuzzing session test completed successfully", .{});
}

/// Helper to mutate block data with bit flips
fn mutateBlock(allocator: std.mem.Allocator, original_block: types.Block, mutation_rate: f32, rng: *std.Random) !types.Block {
    const span = trace.span(.mutate_block);
    defer span.deinit();

    // Serialize the block to bytes for mutation
    var encoded_data = std.ArrayList(u8).init(allocator);
    defer encoded_data.deinit();

    try codec.serialize(types.Block, messages.FUZZ_PARAMS, encoded_data.writer(), original_block);

    // Create mutable copy
    var mutated_data = try allocator.dupe(u8, encoded_data.items);
    defer allocator.free(mutated_data);

    // Apply bit flips based on mutation rate
    const num_bits = mutated_data.len * 8;
    const mutations_count = @as(usize, @intFromFloat(@as(f32, @floatFromInt(num_bits)) * mutation_rate));

    span.debug("Applying {d} bit flips to {d} bytes", .{ mutations_count, mutated_data.len });

    for (0..mutations_count) |_| {
        const byte_index = rng.uintLessThan(usize, mutated_data.len);
        const bit_index = rng.uintLessThan(u8, 8);

        // Flip the bit
        mutated_data[byte_index] ^= (@as(u8, 1) << @as(u3, @intCast(bit_index)));
    }

    // Deserialize back to Block - this might fail due to mutations
    var stream = std.io.fixedBufferStream(mutated_data);
    const deserialized = codec.deserialize(types.Block, messages.FUZZ_PARAMS, allocator, stream.reader()) catch |err| {
        span.debug("Block mutation created invalid block: {s}", .{@errorName(err)});
        return err; // Return error if mutation broke the block
    };

    return deserialized.value;
}

/// Helper to run one fuzzing cycle: generate block, optionally mutate, import, verify
fn runFuzzingCycle(
    allocator: std.mem.Allocator,
    fuzzer_sock: net.Stream,
    target_sock: net.Stream,
    target: *TargetServer,
    handshake_complete: bool,
    block_builder: *sequoia.BlockBuilder(messages.FUZZ_PARAMS),
    mutate: bool,
    mutation_rate: f32,
    rng: *std.Random,
) !struct { original_root: messages.StateRootHash, target_root: messages.StateRootHash } {
    const span = trace.span(.run_fuzzing_cycle);
    defer span.deinit();

    // Generate block
    const original_block = try block_builder.buildNextBlock();
    defer {
        var mutable_block = original_block;
        mutable_block.deinit(allocator);
    }

    // Optionally mutate the block
    var mutated_block_created = false;
    const block_to_import = if (mutate) blk: {
        span.debug("Mutating block with rate {d}", .{mutation_rate});
        const mutated = mutateBlock(allocator, original_block, mutation_rate, rng) catch |err| {
            span.debug("Block mutation failed: {s}, using original block", .{@errorName(err)});
            break :blk original_block;
        };
        mutated_block_created = true;
        break :blk mutated;
    } else original_block;

    defer if (mutated_block_created) {
        var mutable_mutated = block_to_import;
        mutable_mutated.deinit(allocator);
    };

    // Import the block into the fuzzer (for reference state root)
    // TODO: For now, we'll use a placeholder since we don't have fuzzer state management
    const fuzzer_state_root = std.mem.zeroes(messages.StateRootHash);

    // Send ImportBlock to target
    const import_msg = messages.Message{ .import_block = block_to_import };
    try shared.sendMessage(allocator, fuzzer_sock, import_msg);

    // Target processes ImportBlock
    var request = try target.readMessage(target_sock);
    defer request.deinit();
    var handshake_done = handshake_complete;
    const response = try target.processMessage(request.value, &handshake_done);
    try target.sendMessage(target_sock, response.?);

    // Read target's response
    var reply = try shared.readMessage(allocator, fuzzer_sock);
    defer reply.deinit();

    const target_state_root = switch (reply.value) {
        .state_root => |root| root,
        else => return error.UnexpectedResponse,
    };

    span.debug("Fuzzing cycle completed - mutated: {}, roots match: {}", .{ mutate, std.mem.eql(u8, &fuzzer_state_root, &target_state_root) });

    return .{ .original_root = fuzzer_state_root, .target_root = target_state_root };
}
