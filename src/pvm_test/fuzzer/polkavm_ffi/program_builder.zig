const std = @import("std");

pub const ProgramBuilder = struct {
    allocator: std.mem.Allocator,
    ro_data: []const u8,
    rw_data: []const u8,
    code: []const u8,
    jump_table: []const u8,
    bitmask: []const u8,
    exports: []const u8,
    import_offsets: []const u8,
    import_symbols: []const u8,
    debug_strings: []const u8,
    debug_line_programs: []const u8,
    debug_line_ranges: []const u8,
    is_64_bit: bool,
    stack_size: u32,

    pub const Config = struct {
        is_64_bit: bool = false,
        stack_size: u32 = 4096,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        code: []const u8,
        bitmask: []const u8,
        jump_table: []const u8,
        ro_data: []const u8,
        rw_data: []const u8,
        config: Config,
    ) ProgramBuilder {
        return .{
            .allocator = allocator,
            .code = code,
            .bitmask = bitmask,
            .jump_table = jump_table,
            .ro_data = ro_data,
            .rw_data = rw_data,
            .exports = &[_]u8{},
            .import_offsets = &[_]u8{},
            .import_symbols = &[_]u8{},
            .debug_strings = &[_]u8{},
            .debug_line_programs = &[_]u8{},
            .debug_line_ranges = &[_]u8{},
            .is_64_bit = config.is_64_bit,
            .stack_size = config.stack_size,
        };
    }

    pub fn build(self: *const ProgramBuilder) ![]u8 {
        var blob = std.ArrayList(u8).init(self.allocator);
        errdefer blob.deinit();

        // Magic bytes
        try blob.appendSlice("PVM\x00");

        // Version - 0 for 64-bit, 1 for 32-bit
        try blob.append(if (self.is_64_bit) @as(u8, 0) else @as(u8, 1));

        // Length placeholder
        const len_pos = blob.items.len;
        try blob.appendSlice(&[_]u8{0} ** 8);

        // Memory config section
        try blob.append(1); // SECTION_MEMORY_CONFIG
        const config_start = blob.items.len;
        try writeVarInt(blob.writer(), 0); // Section length placeholder
        try writeVarInt(blob.writer(), @intCast(self.ro_data.len));
        try writeVarInt(blob.writer(), @intCast(self.rw_data.len));
        try writeVarInt(blob.writer(), self.stack_size);
        const config_len = blob.items.len - config_start - 1;
        blob.items[config_start] = @intCast(config_len);

        // RO data section
        try blob.append(2); // SECTION_RO_DATA
        try writeVarInt(blob.writer(), @intCast(self.ro_data.len));
        try blob.appendSlice(self.ro_data);

        // RW data section
        try blob.append(3); // SECTION_RW_DATA
        try writeVarInt(blob.writer(), @intCast(self.rw_data.len));
        try blob.appendSlice(self.rw_data);

        // Import section (if any imports exist)
        if (self.import_offsets.len > 0 or self.import_symbols.len > 0) {
            try blob.append(4); // SECTION_IMPORTS
            const import_count = @divExact(self.import_offsets.len, 4);
            const section_size = 1 + // varint size for import count
                self.import_offsets.len +
                self.import_symbols.len;
            try writeVarInt(blob.writer(), @intCast(section_size));
            try writeVarInt(blob.writer(), @intCast(import_count));
            try blob.appendSlice(self.import_offsets);
            try blob.appendSlice(self.import_symbols);
        }

        // Export section (if any)
        if (self.exports.len > 0) {
            try blob.append(5); // SECTION_EXPORTS
            try writeVarInt(blob.writer(), @intCast(self.exports.len));
            try blob.appendSlice(self.exports);
        }

        // Code and jump table section
        try blob.append(6); // SECTION_CODE_AND_JUMP_TABLE
        const jump_entries = @divExact(self.jump_table.len, 4);
        const code_section_size = 1 + // jump table entry count
            1 + // jump table entry size
            std.math.log2_int_ceil(u32, 65536) + // code length
            self.jump_table.len +
            self.code.len +
            self.bitmask.len;

        try writeVarInt(blob.writer(), @intCast(code_section_size));
        try writeVarInt(blob.writer(), @intCast(jump_entries));
        try blob.append(4); // jump table entry size
        try writeVarInt(blob.writer(), @intCast(self.code.len));
        try blob.appendSlice(self.jump_table);
        try blob.appendSlice(self.code);
        try blob.appendSlice(self.bitmask);

        // Debug sections if present
        if (self.debug_strings.len > 0) {
            try blob.append(0x81); // SECTION_OPT_DEBUG_STRINGS
            try writeVarInt(blob.writer(), @intCast(self.debug_strings.len));
            try blob.appendSlice(self.debug_strings);
        }

        if (self.debug_line_programs.len > 0) {
            try blob.append(0x82); // SECTION_OPT_DEBUG_LINE_PROGRAMS
            try writeVarInt(blob.writer(), @intCast(self.debug_line_programs.len));
            try blob.appendSlice(self.debug_line_programs);
        }

        if (self.debug_line_ranges.len > 0) {
            try blob.append(0x83); // SECTION_OPT_DEBUG_LINE_PROGRAM_RANGES
            try writeVarInt(blob.writer(), @intCast(self.debug_line_ranges.len));
            try blob.appendSlice(self.debug_line_ranges);
        }

        // End of file
        try blob.append(0); // SECTION_END_OF_FILE

        // Fill in total length
        const total_len = blob.items.len;
        var len_bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &len_bytes, @intCast(total_len), .little);
        std.mem.copyForwards(u8, blob.items[len_pos .. len_pos + 8], &len_bytes);

        return blob.toOwnedSlice();
    }

    // Helper to set debug info
    pub fn setDebugInfo(
        self: *ProgramBuilder,
        strings: []const u8,
        programs: []const u8,
        ranges: []const u8,
    ) void {
        self.debug_strings = strings;
        self.debug_line_programs = programs;
        self.debug_line_ranges = ranges;
    }

    // Helper to set import info
    pub fn setImports(
        self: *ProgramBuilder,
        offsets: []const u8,
        symbols: []const u8,
    ) void {
        self.import_offsets = offsets;
        self.import_symbols = symbols;
    }

    // Helper to set exports
    pub fn setExports(self: *ProgramBuilder, exports: []const u8) void {
        self.exports = exports;
    }
};

// Helper function to determine the length of a varint based on leading zeros
inline fn getVarintLength(leading_zeros: u32) u32 {
    const bits_required = 32 - leading_zeros;
    const x = bits_required >> 3;
    return ((x + bits_required) ^ x) >> 3;
}

// Writes a varint to a buffer and returns the number of bytes written
fn writeVarInt(writer: anytype, value: u32) !void {
    const varint_length = getVarintLength(@clz(value));

    var value_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &value_bytes, value, .little);

    var buffer: [5]u8 = undefined;
    switch (varint_length) {
        0 => buffer[0] = @truncate(value),
        1 => {
            buffer[0] = 0b10000000 | @as(u8, @truncate(value >> 8));
            buffer[1] = value_bytes[0];
        },
        2 => {
            buffer[0] = 0b11000000 | @as(u8, @truncate(value >> 16));
            buffer[1] = value_bytes[0];
            buffer[2] = value_bytes[1];
        },
        3 => {
            buffer[0] = 0b11100000 | @as(u8, @truncate(value >> 24));
            buffer[1] = value_bytes[0];
            buffer[2] = value_bytes[1];
            buffer[3] = value_bytes[2];
        },
        4 => {
            buffer[0] = 0b11110000;
            buffer[1] = value_bytes[0];
            buffer[2] = value_bytes[1];
            buffer[3] = value_bytes[2];
            buffer[4] = value_bytes[3];
        },
        else => unreachable,
    }

    _ = try writer.write(buffer[0 .. varint_length + 1]);
}
