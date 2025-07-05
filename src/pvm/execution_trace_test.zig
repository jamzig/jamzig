const std = @import("std");
const testing = std.testing;
const PVM = @import("../pvm.zig").PVM;

test "execution_trace_demonstration" {
    const allocator = testing.allocator;
    
    // Create a program using standard format with simple instructions
    // Standard format: RO_size(3) + RW_size(3) + heap_pages(2) + stack_size(3) + RO_data + RW_data + code_len(4) + code
    var program = std.ArrayList(u8).init(allocator);
    defer program.deinit();
    
    // Header: 11 bytes
    try program.writer().writeInt(u24, 0, .little); // read-only size = 0
    try program.writer().writeInt(u24, 0, .little); // read-write size = 0  
    try program.writer().writeInt(u16, 1, .little); // heap pages = 1
    try program.writer().writeInt(u24, 4096, .little); // stack size = 4096
    
    // Code section
    const code_start = program.items.len;
    
    // Write some test instructions:
    // 1. load_imm r1, 42
    try program.appendSlice(&[_]u8{ 0x33, 0x01, 0x2a, 0x00, 0x00, 0x00, 0x00, 0x00 });
    // 2. add_imm_64 r2, r1, -1000 (0xfffffffffffffc18)
    try program.appendSlice(&[_]u8{ 0x8d, 0x02, 0x01, 0x18, 0xfc, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff });
    // 3. store_imm_u32 0x1000, 0x12345678
    try program.appendSlice(&[_]u8{ 0x20, 0x00, 0x10, 0x00, 0x00, 0x78, 0x56, 0x34, 0x12 });
    // 4. jump 5
    try program.appendSlice(&[_]u8{ 0x28, 0x05, 0x00, 0x00, 0x00 });
    // 5. trap (will be skipped)
    try program.appendSlice(&[_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00 });
    // 6. trap (jump target)
    try program.appendSlice(&[_]u8{ 0x00 });
    
    const code_len = program.items.len - code_start;
    
    // Prepend code length
    var final_program = std.ArrayList(u8).init(allocator);
    defer final_program.deinit();
    try final_program.appendSlice(program.items[0..code_start]);
    try final_program.writer().writeInt(u32, @intCast(code_len), .little);
    try final_program.appendSlice(program.items[code_start..]);
    
    var context = try PVM.ExecutionContext.initStandardProgramCodeFormat(
        allocator,
        final_program.items,
        &[_]u8{}, // input
        1000,     // max gas
        false     // dynamic allocation
    );
    defer context.deinit(allocator);
    
    // Enable execution trace manually for testing
    context.exec_trace.enabled = true;
    context.exec_trace.initial_gas = 1000;
    
    // Execute the program with trace output
    std.debug.print("\n=== Execution Trace Demonstration ===\n", .{});
    std.debug.print("Expected format: STEP:NNN PC:XXXXXXXX GAS_COST:N REMAINING:NNN TOTAL_USED:NNN | instruction\n", .{});
    std.debug.print("=====================================\n", .{});
    
    const result = try PVM.basicInvocation(&context);
    
    std.debug.print("=====================================\n", .{});
    std.debug.print("Final state: {} (step_counter={}, total_gas_used={})\n", .{
        result,
        context.exec_trace.step_counter,
        context.exec_trace.total_gas_used,
    });
    std.debug.print("=== End of Trace ===\n\n", .{});
    
    // Verify execution
    try testing.expect(result == .terminal);
    try testing.expect(result.terminal == .halt);
    try testing.expect(context.exec_trace.step_counter > 0);
}

test "execution_trace_with_memory_writes" {
    const allocator = testing.allocator;
    
    // Create program with memory writes
    var program = std.ArrayList(u8).init(allocator);
    defer program.deinit();
    
    // Jump table length (0 entries)
    try program.writer().writeInt(u32, 0, .little);
    
    // Code:
    // store_imm_u8 0x100, 0x42
    try program.appendSlice(&[_]u8{ 0x1e, 0x00, 0x01, 0x00, 0x00, 0x42 });
    // store_imm_u16 0x200, 0x1234
    try program.appendSlice(&[_]u8{ 0x1f, 0x00, 0x02, 0x00, 0x00, 0x34, 0x12 });
    // store_imm_u32 0x300, 0x12345678
    try program.appendSlice(&[_]u8{ 0x20, 0x00, 0x03, 0x00, 0x00, 0x78, 0x56, 0x34, 0x12 });
    // trap
    try program.appendSlice(&[_]u8{ 0x00 });
    
    var context = try PVM.ExecutionContext.initSimple(
        allocator,
        program.items,
        4096, // stack size
        1,    // heap pages
        1000, // max gas
        false // dynamic allocation
    );
    defer context.deinit(allocator);
    
    // Enable execution trace
    context.exec_trace.enabled = true;
    context.exec_trace.initial_gas = 1000;
    context.initRegisters(0);
    
    // Execute with trace output
    std.debug.print("\n=== Execution Trace Test Output ===\n", .{});
    const result = try PVM.basicInvocation(&context);
    std.debug.print("=== End of Trace ===\n\n", .{});
    
    try testing.expect(result == .terminal);
    try testing.expect(result.terminal == .halt);
    try testing.expect(context.exec_trace.step_counter == 4); // 3 stores + 1 trap
}