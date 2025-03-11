const std = @import("std");
const pvmlib = @import("pvm.zig");

const testing = std.testing;

test "pvm:fuzz:instructions" {
    const allocator = std.testing.allocator;
    const polkavm = @import("pvm_test/fuzzer/polkavm_ffi.zig");
    const jumptable = &[_]u32{1};
    const ro_data = &[_]u8{};
    const rw_data = &[_]u8{};

    polkavm.initLogging();

    const InstructionWithArgs = pvmlib.PVM.InstructionWithArgs;

    const instruction = InstructionWithArgs{ .instruction = .add_imm_64, .args = .{
        .TwoRegOneImm = .{
            .first_register_index = 1,
            .second_register_index = 1,
            .immediate = 0xfffffffffffff808,
            .no_of_bytes_to_skip = 3,
        },
    } };

    std.debug.print("Instruction: {s}, first_reg: {}, second_reg: {}, immediate: 0x{x}\n", .{
        @tagName(instruction.instruction),
        instruction.args.TwoRegOneImm.first_register_index,
        instruction.args.TwoRegOneImm.second_register_index,
        instruction.args.TwoRegOneImm.immediate,
    });

    const code = try instruction.encodeOwned();
    std.debug.print("Encoded instruction (len={}): ", .{code.len});
    for (code.asSlice()) |byte| {
        std.debug.print("0x{x:0>2} ", .{byte});
    }
    std.debug.print("\n", .{});

    const bitmask: u8 = @as(u8, 1) << @as(u3, @intCast(code.len));
    std.debug.print("Bitmask: 0x{b:0>2}\n", .{bitmask});

    const raw_program = try polkavm.ProgramBuilder.init(
        allocator,
        code.asSlice(),
        &[_]u8{0b00000001},
        jumptable,
        ro_data,
        rw_data,
        .{},
    ).build();
    defer allocator.free(raw_program);

    std.debug.print("Raw program size: {} bytes: {}\n", .{
        raw_program.len,
        std.fmt.fmtSliceHexLower(raw_program),
    });
    std.debug.print("Raw program size: {} bytes\n", .{raw_program.len});

    const data = try allocator.alloc(u8, 4096);
    defer allocator.free(data);
    const pages = &[_]polkavm.MemoryPage{.{
        .address = 0x20000,
        .data = @ptrCast(data),
        .size = 0x1000,
        .is_writable = true,
    }};
    std.debug.print("Memory page allocated at 0x{x}, size: 0x{x}\n", .{ pages[0].address, pages[0].size });

    var registers: [13]u64 = std.mem.zeroes([13]u64);
    registers[1] = 4278059008;
    std.debug.print("Initial register r1 value: {d}\n", .{registers[1]});

    var executor = try polkavm.Executor.init(raw_program, pages, &registers, 100_000);
    defer executor.deinit();
    std.debug.print("Executor initialized\n", .{});

    std.debug.print("Executing step...\n", .{});
    while (!executor.isFinished()) {
        var result = executor.step();
        defer result.deinit();
        std.debug.print("Final register r1 value: {d}\n", .{result.getRegisters()[1]});
    }
}
