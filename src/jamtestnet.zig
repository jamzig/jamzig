const std = @import("std");
const testing = std.testing;

pub const parsers = @import("jamtestnet/parsers.zig");
pub const state_transitions = @import("jamtestnet/state_transitions.zig");

const stf = @import("stf.zig");
const types = @import("types.zig");
const state = @import("state.zig");
const state_dict = @import("state_dictionary.zig");
const state_delta = @import("state_delta.zig");
const codec = @import("codec.zig");
const services = @import("services.zig");

const jam_params = @import("jam_params.zig");

const jamtestnet = @import("jamtestnet/parsers.zig");

const tracing = @import("tracing.zig");
const trace = tracing.scoped(.stf_test);

// we derive from the normal settings
// see: https://github.com/jam-duna/jamtestnet/blob/main/chainspecs.json#L2
pub const JAMDUNA_PARAMS = jam_params.Params{
    .epoch_length = 12,
    .ticket_submission_end_epoch_slot = 10,
    .validators_count = 6,
    .validators_super_majority = 5,
    .validator_rotation_period = 4,
    .core_count = 2,
    .avail_bitfield_bytes = (2 + 7) / 8,
    // JAMDUNA changes
    .max_tickets_per_extrinsic = 3, // K
    .max_ticket_entries_per_validator = 3, // N
    .max_authorizations_queue_items = 80, // Q
    .max_authorizations_pool_items = 8, // O
    .preimage_expungement_period = 6, // D
};

// Official W3F parameters for tiny configuration traces
pub const W3F_PARAMS = jam_params.Params{
    .validators_count = 6,
    .validators_super_majority = 5, // 2/3 + 1 of 6 validators
    .core_count = 2,
    .avail_bitfield_bytes = 1, // (2 cores + 7) / 8
    .slot_period = 6,
    .epoch_length = 12,
    .ticket_submission_end_epoch_slot = 10, // contest_duration
    .max_ticket_entries_per_validator = 3, // tickets_per_validator
    .max_tickets_per_extrinsic = 3,
    .validator_rotation_period = 4, // rotation_period
    // W3F traces specify 1026 pieces, but with piece size 684 and segment size 4104
    // we actually need: 4104 / 684 = 6 pieces per segment
    .erasure_coded_pieces_per_segment = 6, // num_ec_pieces_per_segment
    // Override D from default 28_800 to 32 as specified in traces README
    .preimage_expungement_period = 32, // D
    // Keep other defaults from jam_params.zig
};
// TODO: add these
// {
//     "tiny": {
//         "segment_size": 4104,
//         "ec_piece_size": 4,
//         "num_ec_pieces_per_segment": 1026,
//     },
//
// test "jamduna:fallback" {
//     const allocator = std.testing.allocator;
//     const loader = jamtestnet.jamduna.Loader(JAMDUNA_PARAMS){};
//     try runStateTransitionTests(
//         JAMDUNA_PARAMS,
//         loader.loader(),
//         allocator,
//         "src/jamtestnet/teams/jamduna/data/fallback/state_transitions",
//     );
// }
//
// test "jamduna:safrole" {
//     const allocator = std.testing.allocator;
//     const loader = jamtestnet.jamduna.Loader(JAMDUNA_PARAMS){};
//     try runStateTransitionTests(
//         JAMDUNA_PARAMS,
//         loader.loader(),
//         allocator,
//         "src/jamtestnet/teams/jamduna/data/safrole/state_transitions",
//     );
// }
//
// test "jamduna:assurances" {
//     const allocator = std.testing.allocator;
//
//     const loader = jamtestnet.jamduna.Loader(JAMDUNA_PARAMS){};
//     try runStateTransitionTests(
//         JAMDUNA_PARAMS,
//         loader.loader(),
//         allocator,
//         "src/jamtestnet/teams/jamduna/data/assurances/state_transitions",
//     );
// }
//
// test "jamduna:orderedaccumulation" {
//     const allocator = std.testing.allocator;
//
//     const loader = jamtestnet.jamduna.Loader(JAMDUNA_PARAMS){};
//     try runStateTransitionTests(
//         JAMDUNA_PARAMS,
//         loader.loader(),
//         allocator,
//         "src/jamtestnet/teams/jamduna/data/orderedaccumulation/state_transitions",
//     );
// }

// // TODO: update
// test "javajam:stf" {
//     const allocator = std.testing.allocator;
//     const loader = jamtestnet.jamduna.Loader(JAMDUNA_PARAMS){};
//     try runStateTransitionTests(
//         JAMDUNA_PARAMS,
//         loader.loader(),
//         allocator,
//         "src/jamtestnet/teams/javajam/stf/state_transitions",
//     );
// }

// TODO: update
// test "jamzig:safrole" {
//     const allocator = std.testing.allocator;
//     const loader = jamtestnet.jamzig.Loader(JAMDUNA_PARAMS){};
//     try runStateTransitionTests(
//         JAMDUNA_PARAMS,
//         loader.loader(),
//         allocator,
//         "src/jamtestnet/teams/jamzig/safrole/state_transitions",
//     );
// }

// W3F Traces Tests
test "w3f:traces:fallback" {
    const allocator = std.testing.allocator;
    const loader = jamtestnet.w3f.Loader(W3F_PARAMS){};
    try runStateTransitionTests(
        W3F_PARAMS,
        loader.loader(),
        allocator,
        "src/jamtestvectors/data/traces/fallback",
    );
}

test "w3f:traces:safrole" {
    const allocator = std.testing.allocator;
    const loader = jamtestnet.w3f.Loader(W3F_PARAMS){};
    try runStateTransitionTests(
        W3F_PARAMS,
        loader.loader(),
        allocator,
        "src/jamtestvectors/data/traces/safrole",
    );
}

test "w3f:traces:reports-l0" {
    const allocator = std.testing.allocator;
    const loader = jamtestnet.w3f.Loader(W3F_PARAMS){};
    try runStateTransitionTests(
        W3F_PARAMS,
        loader.loader(),
        allocator,
        "src/jamtestvectors/data/traces/reports-l0",
    );
}

test "w3f:traces:reports-l1" {
    const allocator = std.testing.allocator;
    const loader = jamtestnet.w3f.Loader(W3F_PARAMS){};
    try runStateTransitionTests(
        W3F_PARAMS,
        loader.loader(),
        allocator,
        "src/jamtestvectors/data/traces/reports-l1",
    );
}

/// Run state transition tests using vectors from the specified directory
pub fn runStateTransitionTests(
    comptime params: jam_params.Params,
    loader: jamtestnet.Loader,
    allocator: std.mem.Allocator,
    test_dir: []const u8,
) !void {
    // Initialize runtime tracing if available
    if (comptime tracing.tracing_mode == .runtime) {
        tracing.runtime.init(allocator);
    }

    std.debug.print("\nRunning state transition tests from: {s}\n", .{test_dir});

    var state_transition_vectors = try jamtestnet.state_transitions.collectStateTransitions(test_dir, allocator);
    defer state_transition_vectors.deinit(allocator);
    std.debug.print("Collected {d} state transition vectors\n", .{state_transition_vectors.items().len});

    var current_state: ?state.JamState(params) = null;
    defer {
        if (current_state) |*cs| cs.deinit(allocator);
    }

    for (state_transition_vectors.items()) |state_transition_vector| {
        // This is sometimes placed in the dir
        if (std.mem.eql(u8, state_transition_vector.bin.name, "genesis.bin")) {
            continue;
        }

        // std.debug.print("\nProcessing transition: {s}\n\n", .{state_transition_vector.bin.name});

        var state_transition = try loader.loadTestVector(allocator, state_transition_vector.bin.path);
        defer state_transition.deinit(allocator);

        // First validate the roots
        var pre_state_mdict = try state_transition.preStateAsMerklizationDict(allocator);
        defer pre_state_mdict.deinit();

        // std.debug.print("{}", .{types.fmt.format(pre_state_mdict)});
        // std.debug.print("{}", .{types.fmt.format(state_transition.block())});

        // Validator Root Calculations
        try state_transition.validateRoots(allocator);

        // std.debug.print("Block header slot: {d}\n", .{state_transition.block.header.slot});

        // Initialize genesis state if needed
        if (current_state == null) {
            // std.debug.print("Initializing genesis state...\n", .{});
            var dict = try state_transition.preStateAsMerklizationDict(allocator);
            defer dict.deinit();
            current_state = try state_dict.reconstruct.reconstructState(
                params,
                allocator,
                &dict,
            );

            var current_state_mdict = try current_state.?.buildStateMerklizationDictionary(allocator);
            defer current_state_mdict.deinit();
            var genesis_state_diff = try current_state_mdict.diff(&dict);
            defer genesis_state_diff.deinit();

            if (genesis_state_diff.has_changes()) {
                std.debug.print("Genesis State Reconstruction Failed. Dict -> Reconstruct -> Dict not symmetrical. Check state encode and decode\n", .{});
                std.debug.print("{}", .{genesis_state_diff});
                return error.GenesisStateDiff;
            }
        }

        // Ensure we are starting with the same roots.
        const pre_state_root = try current_state.?.buildStateRoot(allocator);
        try std.testing.expectEqualSlices(
            u8,
            &state_transition.preStateRoot(),
            &pre_state_root,
        );

        // Print this
        // std.debug.print("{s}\n", .{current_state.?});

        // std.debug.print("Executing state transition...\n", .{});
        // Try state transition, with automatic retry on failure if runtime tracing is enabled
        var transition = try executeStateTransitionWithTracing(
            params,
            allocator,
            &current_state.?,
            &state_transition.block(),
            state_transition_vector.bin.name,
        );
        defer transition.deinitHeap();

        // Merge transition into base state
        try transition.mergePrimeOntoBase();

        // Log block information for debugging
        @import("sequoia.zig").logging.printBlockEntropyDebug(
            params,
            &state_transition.block(),
            &current_state.?,
        );

        // Validate against expected state
        var current_state_mdict = try current_state.?.buildStateMerklizationDictionary(allocator);
        defer current_state_mdict.deinit();

        var expected_state_mdict = try state_transition.postStateAsMerklizationDict(allocator);
        defer expected_state_mdict.deinit();

        var expected_state_diff = try current_state_mdict.diff(&expected_state_mdict);
        defer expected_state_diff.deinit();

        // Check for differences from expected state
        if (expected_state_diff.has_changes()) {
            std.debug.print("{}", .{expected_state_diff});

            var expected_state = try state_dict.reconstruct.reconstructState(params, allocator, &expected_state_mdict);
            defer expected_state.deinit(allocator);

            var state_diff = try @import("tests/state_diff.zig").JamStateDiff(params).build(allocator, &current_state.?, &expected_state);
            defer state_diff.deinit();

            state_diff.printToStdErr();

            // std.debug.print("{}", .{current_state.?});
            // std.debug.print("{}", .{types.fmt.format(current_state.?.delta.?.getAccount(1065941251).?.storageFootprint())});

            return error.UnexpectedStateDiff;
        }

        // Validate state root
        const state_root = try current_state.?.buildStateRoot(allocator);
        try std.testing.expectEqualSlices(
            u8,
            &state_transition.postStateRoot(),
            &state_root,
        );
    }
}

// Execute state transition with automatic tracing on failure
fn executeStateTransitionWithTracing(
    comptime params: jam_params.Params,
    allocator: std.mem.Allocator,
    current_state: *const state.JamState(params),
    block: *const types.Block,
    filename: []const u8,
) !*state_delta.StateTransition(params) {
    // First attempt without tracing
    return stf.stateTransition(params, allocator, current_state, block) catch |err| {
        // Only retry with tracing if runtime mode is enabled
        if (comptime tracing.tracing_mode == .runtime) {
            std.debug.print("\n== STATE TRANSITION FAILED ==\n", .{});
            std.debug.print("Error: {s}\n", .{@errorName(err)});
            std.debug.print("Block slot: {d}\n", .{block.header.slot});
            std.debug.print("File: {s}\n", .{filename});

            // Enable debug tracing for STF modules
            std.debug.print("\nRetrying with debug tracing enabled...\n\n", .{});
            try tracing.runtime.setScope("stf", .debug);
            try tracing.runtime.setScope("safrole", .debug);
            try tracing.runtime.setScope("time", .debug);
            try tracing.runtime.setScope("disputes", .debug);
            try tracing.runtime.setScope("reports", .debug);
            try tracing.runtime.setScope("accumulate", .debug);

            // Retry with tracing enabled
            defer {
                // Disable tracing after retry
                tracing.runtime.disableScope("stf") catch {};
                tracing.runtime.disableScope("safrole") catch {};
                tracing.runtime.disableScope("time") catch {};
                tracing.runtime.disableScope("disputes") catch {};
                tracing.runtime.disableScope("reports") catch {};
                tracing.runtime.disableScope("accumulate") catch {};
            }

            return stf.stateTransition(params, allocator, current_state, block) catch |retry_err| {
                std.debug.print("\n=== Detailed trace above shows failure context ===\n", .{});
                std.debug.print("Error persists: {s}\n\n", .{@errorName(retry_err)});
                return retry_err;
            };
        } else {
            std.debug.print("State transition failed without runtime tracing: {s}\n", .{@errorName(err)});
            return err;
        }
    };
}
