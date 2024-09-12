const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const decoder = @import("codec/decoder.zig");
const Scanner = @import("codec/scanner.zig").Scanner;

pub fn Deserialized(T: anytype) type {
    return struct {
        value: T,
        arena: *std.heap.ArenaAllocator,

        pub fn deinit(self: @This()) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();
            allocator.destroy(self.arena);
        }
    };
}

pub fn deserialize(comptime T: type, parent_allocator: std.mem.Allocator, data: []u8) !Deserialized(T) {
    var result = Deserialized(T){
        .arena = try parent_allocator.create(ArenaAllocator),
        .value = undefined,
    };
    errdefer parent_allocator.destroy(result.arena);
    result.arena.* = ArenaAllocator.init(parent_allocator);
    errdefer result.arena.deinit();

    var scanner = Scanner.initCompleteInput(data);
    result.value = try recursiveDeserializeLeaky(T, result.arena.allocator(), &scanner);

    return result;
}

/// `scanner_or_reader` must be either a `*std.json.Scanner` with complete input or a `*std.json.Reader`.
/// Allocations made during this operation are not carefully tracked and may not be possible to individually clean up.
/// It is recommended to use a `std.heap.ArenaAllocator` or similar.
fn recursiveDeserializeLeaky(comptime T: type, allocator: std.mem.Allocator, scanner: *Scanner) !T {
    switch (@typeInfo(T)) {
        .int => {
            // Handle integer deserialization
            const integer = try decoder.decodeInteger(scanner.remainingBuffer());
            try scanner.advanceCursor(integer.bytes_read);
            return @intCast(integer.value);
        },
        .optional => |optionalInfo| {
            // pub const Optional = struct {
            //     child: type,
            // };
            const present = try scanner.readByte();
            if (present == 0) {
                return null;
            } else if (present == 1) {
                return try recursiveDeserializeLeaky(optionalInfo.child, allocator, scanner);
            } else {
                return error.InvalidValueForOptional;
            }
        },
        .float => {
            // Handle float deserialization
            @compileError("Float deserialization not implemented yet");
        },
        .@"struct" => |structInfo| {
            const fields = structInfo.fields;
            var result: T = undefined;
            inline for (fields) |field| {
                const field_type = field.type;
                const field_value = try recursiveDeserializeLeaky(field_type, allocator, scanner);
                @field(result, field.name) = field_value;
            }
            return result;
        },
        .array => |arrayInfo| {
            if (arrayInfo.sentinel != null) {
                @compileError("Arrays with sentinels are not supported for deserialization");
            }
            return try deserializeArray(arrayInfo.child, arrayInfo.len, scanner);
        },
        .pointer => |pointerInfo| {
            switch (pointerInfo.size) {
                .Slice => {
                    const len = try decoder.decodeInteger(scanner.remainingBuffer());
                    try scanner.advanceCursor(len.bytes_read);
                    std.debug.print("len: {}\n", .{len.value});
                    const slice = try allocator.alloc(pointerInfo.child, @intCast(len.value));
                    for (slice) |*item| {
                        item.* = try recursiveDeserializeLeaky(pointerInfo.child, allocator, scanner);
                    }
                    return slice;
                },
                .One, .Many, .C => {
                    @compileError("Unsupported pointer type for deserialization: " ++ @typeName(T));
                },
            }
        },
        .@"union" => |unionInfo| {
            // unionInfo = struct {
            //     layout: ContainerLayout,
            //     tag_type: ?type,
            //     fields: []const UnionField,
            //     decls: []const Declaration,
            // };
            _ = unionInfo;
            @compileError("Unions are not supported for deserialization");
        },

        else => {
            @compileError("Unsupported type for deserialization: " ++ @typeName(T));
        },
    }
}

fn deserializeArray(comptime T: type, comptime len: usize, scanner: *Scanner) ![len]T {
    var result: [len]T = undefined;
    const bytes_to_read = @sizeOf(T) * len;
    const data = try scanner.readBytes(bytes_to_read);

    // Copy the read bytes into the result array
    @memcpy(&result, data.ptr);

    return result;
}

// Tests
comptime {
    _ = @import("codec/tests.zig");
    _ = @import("codec/encoder/tests.zig");
    _ = @import("codec/decoder/tests.zig");
    _ = @import("codec/encoder.zig");
}
