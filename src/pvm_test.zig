const std = @import("std");
const pvmlib = @import("pvm.zig");

const fixtures = @import("pvm_test/fixtures.zig");

test "pvm:simple" {
    const allocator = std.testing.allocator;

    // -----------------------[0, 0, 33, 4, 8, 1, 4, 9, 1, 5, 3, 0, 2, 119, 255, 7, 7, 12, 82, 138, 8, 152, 8, 82, 169, 5, 243, 82, 135, 4, 8, 4, 9, 17, 19, 0, 73, 147, 82, 213, 254]
    const raw_program = [_]u8{ 0, 0, 33, 4, 8, 1, 4, 9, 1, 5, 3, 0, 2, 119, 255, 7, 7, 12, 82, 138, 8, 152, 8, 82, 169, 5, 243, 82, 135, 4, 8, 4, 9, 17, 19, 0, 73, 147, 82, 213, 254 };

    var pvm = try pvmlib.PVM.init(allocator, &raw_program, std.math.maxInt(u32));
    defer pvm.deinit();

    pvm.registers[0] = 4294901760;
    pvm.registers[7] = 9;

    // std.debug.print("Program: {any}\n", .{pvm.program});

    const result = pvm.run();

    if (result != .halt) {
        std.debug.print("Expected .halt got {any}\n", .{result});
        return error.TestFailed;
    }

    // Check final register values
    const expected_registers = [_]u32{ 4294901760, 0, 0, 0, 0, 0, 0, 55, 0, 0, 34, 0, 0 };

    for (expected_registers, 0..) |expected, i| {
        if (pvm.registers[i] != expected) {
            std.debug.print("Register r{} mismatch. Expected: {}, Got: {}\n", .{ i, expected, pvm.registers[i] });
            return error.TestFailed;
        }
    }
}

test "pvm:inst_add" {
    const allocator = std.testing.allocator;
    const test_result = try fixtures.runTestFixtureFromPath(allocator, "src/tests/vectors/pvm/pvm/pvm/programs/inst_add.json");
    try std.testing.expect(test_result);
}

test "pvm:test_vectors" {
    const TEST_VECTORS = @import("./pvm_test/vectors.zig").TEST_VECTORS;
    const allocator = std.testing.allocator;

    for (TEST_VECTORS) |test_vector| {
        // std.debug.print("Running test vector: {s}\n", .{test_vector});
        const path = try std.fmt.allocPrint(allocator, "src/tests/vectors/pvm/pvm/pvm/programs/{s}", .{test_vector});
        defer allocator.free(path);

        // try printProgramDecompilation(allocator, path);
        const test_result = fixtures.runTestFixtureFromPath(allocator, path) catch |err| {
            std.debug.print("Test {s} failed with error: {}\n", .{ test_vector, err });
            return err;
        };

        if (!test_result) {
            std.debug.print("Test failed for vector: {s}\n", .{test_vector});
            return error.TestFailed;
        }
    }
}

fn printProgramDecompilation(allocator: std.mem.Allocator, path: []const u8) !void {
    const PMVLib = @import("./tests/vectors/libs/pvm.zig");

    const vector = try PMVLib.PVMTestVector.build_from(allocator, path);
    defer vector.deinit();

    var pvm = try pvmlib.PVM.init(allocator, vector.value.program, std.math.maxInt(u32));
    defer pvm.deinit();

    std.debug.print("Program decompilation:\n", .{});
    try pvm.decompilePrint();
}
