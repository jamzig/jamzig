const std = @import("std");
const Allocator = std.mem.Allocator;
const Instruction = @import("./pvm/instruction.zig").Instruction;
const Program = @import("./pvm/program.zig").Program;
const Decoder = @import("./pvm/decoder.zig").Decoder;

pub const PVM = struct {
    allocator: *Allocator,
    program: Program,
    registers: [13]u64,
    pc: usize,
    memory: []u8,

    pub fn init(allocator: *Allocator, raw_program: []const u8) !PVM {
        const program = try Program.decode(allocator, raw_program);

        return PVM{
            .allocator = allocator,
            .program = program,
            .registers = [_]u64{0} ** 13,
            .pc = 0,
            .memory = try allocator.alloc(u8, 1024 * 1024), // Allocate 1MB of memory
        };
    }

    pub fn deinit(self: *PVM) void {
        self.program.deinit(self.allocator);
        self.allocator.free(self.memory);
    }

    pub fn run(self: *PVM) !void {
        const decoder = Decoder.init(self.program.code, self.program.mask);
        while (self.pc < self.program.code.len) {
            const i = try decoder.decodeInstruction(self.pc);

            std.debug.print("{d:0>4}: {any}\n", .{ self.pc, i });

            self.pc += i.skip_l() + 1;
        }
    }
};
