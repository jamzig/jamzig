const std = @import("std");
const testing = std.testing;
const types = @import("types.zig");

const state = @import("state.zig");
const state_delta = @import("state_delta.zig");
const jam_params = @import("jam_params.zig");

const authorizations = @import("authorizations.zig");
const auth_pool = @import("authorizer_pool.zig");
const auth_queue = @import("authorizer_queue.zig");

const jamtestvectors = @import("jamtestvectors/authorizations.zig");

const converters = @import("authorizations_test/converters.zig");

const trace = @import("tracing.zig").scoped(.authorizations_test);

test "authorizations:verify with multiple test vectors" {
    const allocator = testing.allocator;
    const params = jam_params.TINY_PARAMS;

    const test_paths = [_][]const u8{
        "src/jamtestvectors/data/authorizations/tiny/progress_authorizations-1.bin",
        "src/jamtestvectors/data/authorizations/tiny/progress_authorizations-2.bin",
        "src/jamtestvectors/data/authorizations/tiny/progress_authorizations-3.bin",
    };

    for (test_paths) |test_path| {
        // Load test vector
        var test_vector = try jamtestvectors.TestCase(params).buildFrom(
            allocator,
            test_path,
        );
        defer test_vector.deinit(allocator);

        // try test_vector.debugPrintStateDiff(allocator);
        test_vector.debugInput();

        var current_state = try converters.buildTransientFromTestState(params, allocator, test_vector.pre_state);
        defer current_state.deinit(allocator);

        var transition = try state_delta.StateTransition(params).init(
            allocator,
            &current_state,
            params.Time().init(test_vector.input.slot - 1, test_vector.input.slot),
        );
        defer transition.deinit();

        // Process authorizations
        const auths = try converters.convertToAuthorizerList(allocator, test_vector.input);
        defer allocator.free(auths);

        try authorizations.processAuthorizations(
            params,
            &transition,
            auths,
        );

        try transition.mergePrimeOntoBase();

        var expected_state = try converters.buildTransientFromTestState(params, allocator, test_vector.post_state);
        defer expected_state.deinit(allocator);

        var diff = try @import("tests/diff.zig").diffBasedOnFormat(
            allocator,
            current_state,
            expected_state,
        );
        defer diff.deinit(allocator);

        try diff.debugPrintAndReturnErrorOnDiff();
    }
}
