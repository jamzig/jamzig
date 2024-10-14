const std = @import("std");
const tvector = @import("tests/vectors/libs/disputes.zig");

const diffz = @import("disputes_test/diffz.zig");
const converters = @import("disputes_test/converters.zig");

const disputes = @import("disputes.zig");

const stf = @import("stf.zig");

fn printStateDiff(allocator: std.mem.Allocator, pre_state: *const tvector.State, post_state: *const tvector.State) !void {
    const state_diff = try diffz.diffStates(allocator, pre_state, post_state);
    defer allocator.free(state_diff);
    std.debug.print("\nState Diff: {s}\n", .{state_diff});
}

pub const TINY_PARAMS = @import("jam_params.zig").Params{
    .epoch_length = 12,
    // TODO: what value of Y (ticket_submission_end_slot) should we use for the tiny vectors, now set to
    // same ratio. Production values is 500 of and epohc length of 600 which
    // would suggest 10
    .ticket_submission_end_epoch_slot = 10,
    .max_ticket_entries_per_validator = 2,
    .validators_count = 6,
};

fn runDisputeTest(allocator: std.mem.Allocator, test_vector: tvector.TestVector) !void {
    var current_psi = try converters.convertPsi(allocator, test_vector.pre_state.psi);
    defer current_psi.deinit();
    var expected_psi = try converters.convertPsi(allocator, test_vector.post_state.psi);
    defer expected_psi.deinit();
    var extrinsic_disputes = try converters.convertDisputesExtrinsic(allocator, test_vector.input.disputes);
    defer extrinsic_disputes.deinit(allocator);

    const kappa = try converters.convertValidatorData(allocator, test_vector.pre_state.kappa);
    defer allocator.free(kappa);

    const lambda = try converters.convertValidatorData(allocator, test_vector.pre_state.lambda);
    defer allocator.free(lambda);

    const current_epoch = test_vector.pre_state.tau / TINY_PARAMS.epoch_length;
    const transition_result = stf.transitionDisputes(allocator, 6, &current_psi, kappa, lambda, current_epoch, extrinsic_disputes);

    defer {
        if (transition_result) |psi| {
            defer @constCast(&psi).deinit();
        } else |_| {} // this needs to be here to satisfy the compiler
    }

    switch (test_vector.output) {
        .err => |expected_error| {
            if (transition_result) |_| {
                std.debug.print("\nGot a success, expected error: {any}\n", .{expected_error});
                return error.UnexpectedSuccess;
            } else |actual_error| {
                const mapped_expected_error = switch (expected_error) {
                    .already_judged => error.AlreadyJudged,
                    .bad_vote_split => error.BadVoteSplit,
                    .verdicts_not_sorted_unique => error.VerdictsNotSortedUnique,
                    .judgements_not_sorted_unique => error.JudgementsNotSortedUnique,
                    .culprits_not_sorted_unique => error.CulpritsNotSortedUnique,
                    .faults_not_sorted_unique => error.FaultsNotSortedUnique,
                    .not_enough_culprits => error.NotEnoughCulprits,
                    .not_enough_faults => error.NotEnoughFaults,
                    .culprits_verdict_not_bad => error.CulpritsVerdictNotBad,
                    .fault_verdict_wrong => error.FaultVerdictWrong,
                    .offender_already_reported => error.OffenderAlreadyReported,
                    .bad_judgement_age => error.BadJudgementAge,
                    .bad_validator_index => error.BadValidatorIndex,
                    .bad_signature => error.BadSignature,
                };
                std.debug.print("\nExpected error: {any}\n", .{expected_error});
                try std.testing.expectEqual(mapped_expected_error, actual_error);
            }
        },
        .ok => |expected_marks| {
            if (transition_result) |transitioned_psi| {
                // push all expected marks in an AutoHashMap
                var expected_marks_map = std.AutoHashMap(disputes.PublicKey, void).init(allocator);
                defer expected_marks_map.deinit();

                for (expected_marks.offenders_mark) |mark| {
                    try expected_marks_map.put(mark.bytes, {});
                }

                try std.testing.expectEqualDeep(expected_marks_map, transitioned_psi.punish_set);

                // Compare the rest of the fields
                try std.testing.expectEqualDeep(expected_psi.good_set, transitioned_psi.good_set);
                try std.testing.expectEqualDeep(expected_psi.bad_set, transitioned_psi.bad_set);
                try std.testing.expectEqualDeep(expected_psi.wonky_set, transitioned_psi.wonky_set);
            } else |err| {
                std.debug.print("UnexpectedError: {any}\n", .{err});
                return error.UnexpectedError;
            }
        },
    }
}

test "tiny/progress_with_no_verdicts-1.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_no_verdicts-1.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );

    try runDisputeTest(allocator, test_vector.value);
}

test "tiny/progress_with_bad_signatures-1.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_bad_signatures-1.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
    //

    try runDisputeTest(allocator, test_vector.value);
}

test "tiny/progress_with_bad_signatures-2.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_bad_signatures-2.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_culprits-1.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_culprits-1.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_culprits-2.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_culprits-2.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_culprits-3.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_culprits-3.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_culprits-4.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_culprits-4.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_culprits-5.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_culprits-5.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_culprits-6.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_culprits-6.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_culprits-7.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_culprits-7.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_faults-1.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_faults-1.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_faults-2.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_faults-2.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_faults-3.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_faults-3.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_faults-4.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_faults-4.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_faults-5.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_faults-5.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_faults-6.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_faults-6.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_faults-7.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_faults-7.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_verdict_signatures_from_previous_set-1.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_verdict_signatures_from_previous_set-1.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_verdict_signatures_from_previous_set-2.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_verdict_signatures_from_previous_set-2.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_verdicts-1.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_verdicts-1.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_verdicts-2.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_verdicts-2.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_verdicts-3.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_verdicts-3.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_verdicts-4.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_verdicts-4.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_verdicts-5.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_verdicts-5.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

test "tiny/progress_with_verdicts-6.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_with_verdicts-6.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}

// This test is the only one which will change the rho, the rest is Phi.only
test "tiny/progress_invalidates_avail_assignments-1.json" {
    const allocator = std.testing.allocator;
    const test_json = "src/tests/vectors/disputes/disputes/tiny/progress_invalidates_avail_assignments-1.json";
    const test_vector = try tvector.TestVector.build_from(allocator, test_json);
    defer test_vector.deinit();

    return error.NotImplementedYet;

    // try printStateDiff(
    //     allocator,
    //     &test_vector.value.pre_state,
    //     &test_vector.value.post_state,
    // );
}
