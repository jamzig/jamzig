const std = @import("std");
const safrole = @import("adaptor.zig");
const fixtures = @import("fixtures.zig");
const assert = std.debug.assert;
const Params = @import("../jam_params.zig").Params;

pub fn runSafroleTest(
    comptime params: Params,
    allocator: std.mem.Allocator,
    bin_file_path: []const u8,
) !void {
    var fixture = try fixtures.buildFixtures(params, allocator, bin_file_path);
    defer fixture.deinit();

    const actual_result = try safrole.transition(
        params,
        allocator,
        fixture.pre_state,
        fixture.input,
    );
    defer actual_result.deinit(allocator);

    // Compare outputs
    fixture.expectOutput(actual_result.output) catch |err| {
        std.debug.print("\n❌ Output mismatch for {s}\n", .{bin_file_path});
        // std.debug.print("Expected output: {any}\n", .{fixture.output});
        // std.debug.print("Actual output: {any}\n", .{actual_result.output});
        std.debug.print("Error: {any}\n", .{err});
        try fixture.printInputStateChangesAndOutput();
        std.debug.print("\n\n", .{});
        return err;
    };

    // Compare post states if available
    if (actual_result.state) |state| {
        fixture.expectPostState(&state) catch |err| {
            std.debug.print("\n❌ Post-state mismatch for {s}\n", .{bin_file_path});
            try fixture.diffAgainstPostStateAndPrint(&state.gamma);
            std.debug.print("Error: {any}\n", .{err});
            try fixture.printInputStateChangesAndOutput();
            return err;
        };
    }

    // Print success message
    std.debug.print("\n✅ Test passed: {s}\n", .{bin_file_path});
}

pub fn runSafroleTestDir(
    comptime params: Params,
    allocator: std.mem.Allocator,
    dir_path: []const u8,
) !void {
    const ordered_files = @import("../tests/ordered_files.zig");

    var file_list = try ordered_files.getOrderedFiles(allocator, dir_path);
    defer file_list.deinit();

    var failed_tests = std.ArrayList([]const u8).init(allocator);
    defer failed_tests.deinit();

    var test_count: usize = 0;
    var pass_count: usize = 0;

    for (file_list.items()) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".bin")) continue;

        test_count += 1;
        runSafroleTest(params, allocator, entry.path) catch {
            const failed_test = try allocator.dupe(u8, entry.path);
            try failed_tests.append(failed_test);
            break;
        };
        pass_count += 1;
    }

    // Print summary
    std.debug.print("\n=== Test Summary ===\n", .{});
    std.debug.print("Total tests: {d}\n", .{test_count});
    std.debug.print("Passed: {d}\n", .{pass_count});
    std.debug.print("Failed: {d}\n", .{test_count - pass_count});

    if (failed_tests.items.len > 0) {
        std.debug.print("\nFailed tests:\n", .{});
        for (failed_tests.items) |failed_test| {
            std.debug.print("❌ {s}\n", .{failed_test});
            allocator.free(failed_test);
        }
        return error.TestsFailed;
    }
}

test "tiny: Run tiny safrole tests" {
    try runSafroleTestDir(
        @import("../jam_params.zig").TINY_PARAMS,
        std.testing.allocator,
        "src/jamtestvectors/data/safrole/tiny",
    );
}

test "full: Run full safrole tests" {
    try runSafroleTestDir(
        @import("../jam_params.zig").FULL_PARAMS,
        std.testing.allocator,
        "src/jamtestvectors/data/safrole/full",
    );
}
