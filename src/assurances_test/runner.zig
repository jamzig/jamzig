const std = @import("std");
const converters = @import("./converters.zig");
const tvector = @import("../jamtestvectors/assurances.zig");
const assurances = @import("../assurances.zig");
const types = @import("../types.zig");
const helpers = @import("../tests/helpers.zig");
const diff = @import("../tests/diff.zig");
const Params = @import("../jam_params.zig").Params;

pub fn runAssuranceTest(comptime params: Params, allocator: std.mem.Allocator, test_case: tvector.TestCase) !void {
    // Convert pre-state from test vector format to native format
    var pre_state_assignments = try converters.convertAvailabilityAssignments(
        params.core_count,
        allocator,
        test_case.pre_state.avail_assignments,
    );
    defer pre_state_assignments.deinit();

    var pre_state_validators = try converters.convertValidatorSet(allocator, test_case.pre_state.curr_validators);
    defer pre_state_validators.deinit(allocator);

    // Convert post-state for later comparison
    var expected_assignments = try converters.convertAvailabilityAssignments(
        params.core_count,
        allocator,
        test_case.post_state.avail_assignments,
    );
    defer expected_assignments.deinit();

    var expected_validators = try converters.convertValidatorSet(allocator, test_case.post_state.curr_validators);
    defer expected_validators.deinit(allocator);

    // First validate the assurance extrinsic
    const validated_extrinsic = assurances.ValidatedAssuranceExtrinsic.validate(
        params,
        test_case.input.assurances,
        test_case.input.parent,
        pre_state_validators,
    );

    switch (test_case.output) {
        .err => |expected_error| {
            if (validated_extrinsic) |_| {
                std.debug.print("\nGot a success, expected error: {any}\n", .{expected_error});
                return error.UnexpectedSuccess;
            } else |actual_error| {
                const mapped_expected_error = switch (expected_error) {
                    .bad_attestation_parent => error.InvalidAnchorHash,
                    .bad_validator_index => error.InvalidValidatorIndex,
                    .core_not_engaged => error.InvalidBitfieldSize,
                    .bad_signature => error.InvalidSignature,
                    .not_sorted_or_unique_assurers => error.NotSortedValidatorIndex,
                };
                std.debug.print("\nExpected error: {any} => {any} got error {any}\n", .{ expected_error, mapped_expected_error, actual_error });
                try std.testing.expectEqual(mapped_expected_error, actual_error);
            }
        },
        .ok => |expected_marks| {
            if (validated_extrinsic) |valid_extrinsic| {
                const state_rho = &pre_state_assignments;
                const state_kappa = &pre_state_validators;

                // Process the validated extrinsic
                const available_reports = try assurances.processAssuranceExtrinsic(
                    params,
                    allocator,
                    valid_extrinsic,
                    test_case.input.slot,
                    state_rho,
                );
                defer allocator.free(available_reports);

                // Verify outputs match expected results
                if (available_reports.len != expected_marks.reported.len) {
                    std.debug.print("\nMismatch in number of reports:\n  Expected: {d}\n  Got: {d}\n", .{
                        expected_marks.reported.len,
                        available_reports.len,
                    });
                    return error.ReportCountMismatch;
                }

                for (available_reports, expected_marks.reported) |actual, expected| {
                    diff.expectFormattedEqual(allocator, actual.report, expected) catch {
                        return error.ReportMismatch;
                    };
                }

                // Verify state matches expected state
                diff.expectFormattedEqual(allocator, state_rho, &expected_assignments) catch {
                    return error.StateRhoMismatch;
                };

                diff.expectFormattedEqual(allocator, state_kappa, &expected_validators) catch {
                    return error.StateKappaMismatch;
                };
            } else |err| {
                std.debug.print("UnexpectedError: {any}\n", .{err});
                return error.UnexpectedError;
            }
        },
    }
}
