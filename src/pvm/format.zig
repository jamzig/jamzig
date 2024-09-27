const Program = @import("program.zig").Program;

pub fn formatProgram(self: *const Program, writer: anytype) !void {
    try writer.print("Jump Table (length: {}, item length: {} bytes):\n", .{
        self.jump_table.len,
        self.jump_table_item_length,
    });
    var i: usize = 0;
    while (i < self.jump_table.len) : (i += self.jump_table_item_length) {
        try writer.print("  {}: ", .{i / self.jump_table_item_length});
        for (self.jump_table[i..][0..self.jump_table_item_length]) |byte| {
            try writer.print("{X:0>2}", .{byte});
        }
        try writer.writeByte('\n');
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
