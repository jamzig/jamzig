const std = @import("std");
const InstructionWithArgs = @import("decoder.zig").InstructionWithArgs;

/// Execution trace state for detailed VM execution logging
pub const ExecutionTrace = struct {
    step_counter: u32 = 0,
    initial_gas: i64 = 0,
    total_gas_used: i64 = 0,
    previous_registers: [13]u64 = [_]u64{0} ** 13,
    enabled: bool = false,

    const Self = @This();

    /// Initialize the execution trace with starting gas
    pub fn init(initial_gas: i64, enabled: bool) Self {
        return .{
            .initial_gas = initial_gas,
            .enabled = enabled,
        };
    }

    /// Log an execution step with standardized format
    pub fn logStep(
        self: *Self,
        pc: u32,
        gas_before: i64,
        gas_after: i64,
        instruction: *const InstructionWithArgs,
    ) void {
        if (!self.enabled) return;

        self.step_counter += 1;
        const gas_cost = gas_before - gas_after;
        self.total_gas_used += @intCast(gas_cost);

        // Use custom formatter for cleaner output
        var buf: [256]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buf);
        formatInstructionSimple(instruction, stream.writer()) catch return;

        std.debug.print("STEP:{d:0>3} PC:{d:0>8} GAS_COST:{} REMAINING:{} TOTAL_USED:{} | {s}\n", .{
            self.step_counter,
            pc,
            gas_cost,
            gas_after,
            self.total_gas_used,
            stream.getWritten(),
        });
    }

    /// Log a memory write operation
    pub fn logMemoryWrite(
        self: *const Self,
        addr: u32,
        value: u64,
        size: usize,
    ) void {
        if (!self.enabled) return;

        std.debug.print("MEM_WRITE: addr=0x{x:0>8} value=0x{x} size={}\n", .{ addr, value, size });
    }

    /// Log a memory write with slice data
    pub fn logMemoryWriteSlice(
        self: *const Self,
        addr: u32,
        data: []const u8,
    ) void {
        if (!self.enabled) return;

        // For slices, show first 8 bytes as hex if available
        if (data.len >= 8) {
            const value = std.mem.readInt(u64, data[0..8], .little);
            std.debug.print("MEM_WRITE: addr=0x{x:0>8} value=0x{x} size={}\n", .{ addr, value, data.len });
        } else if (data.len > 0) {
            var value: u64 = 0;
            for (data, 0..) |byte, i| {
                value |= @as(u64, byte) << @intCast(i * 8);
            }
            std.debug.print("MEM_WRITE: addr=0x{x:0>8} value=0x{x} size={}\n", .{ addr, value, data.len });
        }
    }

    /// Check and log register changes
    pub fn checkRegisterChanges(
        self: *Self,
        current_registers: *const [13]u64,
    ) void {
        if (!self.enabled) return;

        for (current_registers, 0..) |reg_value, i| {
            if (reg_value != self.previous_registers[i]) {
                std.debug.print("REG_CHANGE: r{}=0x{x}\n", .{ i, reg_value });
                self.previous_registers[i] = reg_value;
            }
        }
    }

    /// Log a host call
    pub fn logHostCall(
        self: *const Self,
        call_type: []const u8,
        selector: u32,
        gas_charged: i64,
    ) void {
        if (!self.enabled) return;

        std.debug.print("HOST_CALL: {s} selector={} gas_charged={}\n", .{ call_type, selector, gas_charged });
    }

    /// Initialize register tracking with current values
    pub fn initRegisterTracking(self: *Self, registers: *const [13]u64) void {
        self.previous_registers = registers.*;
    }
};

/// Format instruction in simplified form for execution traces
fn formatInstructionSimple(
    instruction: *const InstructionWithArgs,
    writer: anytype,
) !void {
    try writer.print("{s}", .{@tagName(instruction.instruction)});

    switch (instruction.args) {
        .NoArgs => {},
        .OneImm => |args| try writer.print(" {}", .{args.immediate}),
        .OneOffset => |args| try writer.print(" {}", .{args.offset}),
        .OneRegOneImm => |args| {
            if (args.immediate > 0xFFFF or
                (args.immediate > 0x7FFF and @as(i64, @bitCast(args.immediate)) < 0))
            {
                // Large or negative immediates in hex
                try writer.print(" r{}, 0x{x}", .{ args.register_index, args.immediate });
            } else {
                try writer.print(" r{}, {}", .{ args.register_index, args.immediate });
            }
        },
        .OneRegOneImmOneOffset => |args| {
            if (args.immediate > 0xFFFF or
                (args.immediate > 0x7FFF and @as(i64, @bitCast(args.immediate)) < 0))
            {
                try writer.print(" r{}, 0x{x}, {}", .{ args.register_index, args.immediate, args.offset });
            } else {
                try writer.print(" r{}, {}, {}", .{ args.register_index, args.immediate, args.offset });
            }
        },
        .OneRegOneExtImm => |args| {
            if (args.immediate > 0xFFFF or
                (args.immediate > 0x7FFF and @as(i64, @bitCast(args.immediate)) < 0))
            {
                try writer.print(" r{}, 0x{x}", .{ args.register_index, args.immediate });
            } else {
                try writer.print(" r{}, {}", .{ args.register_index, args.immediate });
            }
        },
        .OneRegTwoImm => |args| try writer.print(" r{}, {}, {}", .{ args.register_index, args.first_immediate, args.second_immediate }),
        .ThreeReg => |args| try writer.print(" r{}, r{}, r{}", .{ args.first_register_index, args.second_register_index, args.third_register_index }),
        .TwoImm => |args| try writer.print(" {}, {}", .{ args.first_immediate, args.second_immediate }),
        .TwoReg => |args| try writer.print(" r{}, r{}", .{ args.first_register_index, args.second_register_index }),
        .TwoRegOneImm => |args| {
            if (args.immediate > 0xFFFF or
                (args.immediate > 0x7FFF and @as(i64, @bitCast(args.immediate)) < 0))
            {
                try writer.print(" r{}, r{}, 0x{x}", .{ args.first_register_index, args.second_register_index, args.immediate });
            } else {
                try writer.print(" r{}, r{}, {}", .{ args.first_register_index, args.second_register_index, args.immediate });
            }
        },
        .TwoRegOneOffset => |args| try writer.print(" r{}, r{}, {}", .{ args.first_register_index, args.second_register_index, args.offset }),
        .TwoRegTwoImm => |args| try writer.print(" r{}, r{}, {}, {}", .{ args.first_register_index, args.second_register_index, args.first_immediate, args.second_immediate }),
    }
}

