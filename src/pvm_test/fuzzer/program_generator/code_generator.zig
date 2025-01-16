const std = @import("std");

const SeedGenerator = @import("../seed.zig").SeedGenerator;

const igen = @import("instruction_generator.zig");
const InstructionWithArgs = @import("../../../pvm/instruction.zig").InstructionWithArgs;

/// Generate a sequence of random instructions
pub fn generate(allocator: std.mem.Allocator, seed_gen: *SeedGenerator, instruction_count: usize) ![]InstructionWithArgs {
    var instructions = try std.ArrayList(InstructionWithArgs).initCapacity(
        allocator,
        instruction_count,
    );
    defer instructions.deinit();

    // Generate a sequence of valid instructions
    for (0..instruction_count) |_| {
        try instructions.append(igen.randomInstruction(seed_gen));
    }

    return try instructions.toOwnedSlice();
}
