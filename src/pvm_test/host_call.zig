const std = @import("std");
const pvmlib = @import("../pvm.zig");

fn testHostCall(gas: *i64, registers: *[13]u64, page_map: []pvmlib.PVM.PageMap) pvmlib.PMVHostCallResult {
    _ = page_map;
    _ = gas;
    // std.debug.print("Host call\n", .{});
    // Simple host call that adds 1 to the first register
    registers[0] += 1;
    return .play;
}

test "pvm:ecalli:host_call" {
    const allocator = std.testing.allocator;

    // Create a simple program that makes a host call
    const ecalli: []const u8 = @embedFile("pvm_test/fixtures/jampvm/ecalli.jampvm");

    var pvm = try pvmlib.PVM.init(allocator, ecalli, 1000);
    defer pvm.deinit();

    // See the program
    // try pvm.decompilePrint();

    // Register the host call
    try pvm.registerHostCall(0, testHostCall);

    // Set up initial register value
    pvm.registers[0] = 42;

    // Run the program
    const status = pvm.run();

    // Check the results
    try std.testing.expectEqual(pvmlib.PVM.Status.panic, status);
    try std.testing.expectEqual(@as(u32, 43), pvm.registers[0]);
}

test "pvm:ecalli:host_call:add" {
    const allocator = std.testing.allocator;

    // Create a simple program that makes a host call
    // and afterwards updates the register some more to test continuation
    const ecalli_and_add: []const u8 = @embedFile("pvm_test/fixtures/jampvm/ecalli_and_add.jampvm");

    var pvm = try pvmlib.PVM.init(allocator, ecalli_and_add, 1000);
    defer pvm.deinit();

    // See the program
    // try pvm.decompilePrint();

    // Register the host call
    try pvm.registerHostCall(0, testHostCall);

    // Set up initial register value
    pvm.registers[0] = 42;

    // Run the program, this does the hostcall and then adds 1 to the register
    const status = pvm.run();

    // Check the results
    try std.testing.expectEqual(pvmlib.PVM.Status.panic, status);
    try std.testing.expectEqual(@as(u32, 44), pvm.registers[0]);
}
