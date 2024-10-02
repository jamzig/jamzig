const Program = @import("program.zig").Program;

pub fn formatProgram(self: *const Program, writer: anytype) !void {
    try writer.print("Jump Table (length: {}):\n", .{
        self.jump_table.len(),
    });
    for (0..self.jump_table.len()) |index| {
        const jump_target = self.jump_table.getDestination(index);
        try writer.print("  {}: {}\n", .{ index, jump_target });
    }

    try writer.print("\nCode (length: {} bytes):\n", .{self.code.len});
    for (self.code, 0..) |byte, index| {
        if (index % 16 == 0) {
            if (index > 0) try writer.writeByte('\n');
            try writer.print("  {X:0>4}: ", .{index});
        }
        try writer.print("{X:0>2} ", .{byte});
    }
    try writer.writeByte('\n');

    try writer.print("\nMask (length: {} bytes):\n", .{self.mask.len});
    for (self.mask, 0..) |byte, index| {
        if (index % 16 == 0) {
            if (index > 0) try writer.writeByte('\n');
            try writer.print("  {X:0>4}: ", .{index});
        }
        try writer.print("{b:0>8} ", .{byte});
    }
    try writer.writeByte('\n');
}
