const std = @import("std");
const testing = std.testing;
const Instruction = @import("../../../pvm/instruction.zig").Instruction;
const Decoder = @import("../../../pvm/decoder.zig").Decoder;
const encoder = @import("instruction_encoder.zig").encoder;

const InstructionType = @import("instruction.zig").InstructionType;
const InstructionRanges = @import("instruction.zig").InstructionRanges;

test "instruction roundtrip tests" {
    inline for (std.meta.fields(InstructionType)) |field| {
        // Get the instruction type name
        const type_name = field.name;
        // Get the range for this type
        const range = comptime InstructionRanges.get(type_name).?;

        // Static test function for each instruction type
        // const test_name = "test_" ++ type_name;

        // Test each opcode in the range
        comptime var opcode = range.start;
        inline while (opcode <= range.end) : (opcode += 1) {
            // Here we'll add the encode/decode test logic

            var program: [16]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&program);
            var enc = encoder(fbs.writer());

            // const encodeFn = @FieldType(@TypeOf(enc), "encode" ++ field.name);
            const encodeFn = @field(@TypeOf(enc), "encode" ++ field.name);
            const EncodeFnParams = std.meta.ArgsTuple(@TypeOf(encodeFn));

            var encodeFnParams = comptime blk: {
                var params: EncodeFnParams = undefined;
                params[1] = opcode; // First parameter is always opcode

                // Fill in the rest of the parameters based on their types
                var i = 2;
                while (i < std.meta.fields(EncodeFnParams).len) : (i += 1) {
                    const param_type = @TypeOf(params[i]);
                    params[i] = switch (param_type) {
                        u8 => 0x05, // Register
                        u32 => 0x234, // Immediate
                        i32 => 0x456, // Immediate
                        else => @compileError("Unexpected parameter type: " ++ @typeName(param_type)),
                    };
                }
                break :blk params;
            };

            std.debug.print("\nTesting {s} (opcode: {d})\n", .{ type_name, opcode });

            encodeFnParams[0] = &enc;
            const length = try @call(.auto, encodeFn, encodeFnParams);
            _ = try enc.encodeNoArgs(1);
            const written = fbs.getWritten();

            var mask: [16]u8 = std.mem.zeroes([16]u8);
            mask[length / 8] |= @as(u8, 0x01) << @intCast(length % 8);

            const dec = Decoder.init(written, &mask);
            const instruction = try dec.decodeInstruction(0);

            std.debug.print("{s}\n", .{instruction});
        }
    }
}
