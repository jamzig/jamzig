const std = @import("std");

pub fn deserialize(comptime T: type, data: []u8) !T {
    _ = data;
    return error.NotImplemented;
}

/// (271) Function to encode an integer into a specified number of octets in
/// little-endian format
pub fn encodeFixedLengthInteger(x: anytype) [@sizeOf(@TypeOf(x))]u8 {
    const L = @sizeOf(@TypeOf(x)); // Determine the size of the value in bytes
    return encodeFixedLengthIntegerWithSize(L, x);
}

fn encodeFixedLengthIntegerWithSize(comptime L: usize, x: anytype) [L]u8 {
    var result: [L]u8 = undefined;

    if (L == 1) {
        result[0] = @intCast(x);
        return result;
    }

    var value: @TypeOf(x) = x;
    var i: usize = 0;

    while (i < L) : (i += 1) {
        result[i] = @intCast(value & 0xff);
        value >>= 8;
    }

    return result;
}

/// Encoding result as specified in the encoding section of the gray paper
/// can hold up to 9 bytes of data including the prefix, allowing it to store
/// values up to 2^64.
pub const EncodingResult = struct {
    data: [9]u8,
    len: u8,

    pub fn build(prefix: ?u8, init_data: []const u8) @This() {
        var self: EncodingResult = .{
            .len = undefined,
            .data = undefined,
        };
        if (prefix) |pre| {
            self.data[0] = pre;
            std.mem.copyForwards(u8, self.data[1..], init_data);
            self.len = @intCast(init_data.len + 1);
        } else {
            std.mem.copyForwards(u8, &self.data, init_data);
            self.len = @intCast(init_data.len);
        }
        return self;
    }

    pub fn as_slice(self: *const @This()) []const u8 {
        return self.data[0..@intCast(self.len)];
    }
};

/// (272) Function to encode an integer (0 to 2^64) into a variable-length.
/// Will return an `EncodingResult` with the possible outcomes. This function will mainly be used
/// to store the length prefixes.
const find_l = @import("codec/util.zig").find_l;
const encode_l = @import("codec/util.zig").encode_l;
pub fn encodeInteger(x: anytype) EncodingResult {
    if (x == 0) {
        return EncodingResult.build(null, &[_]u8{0});
    } else if (find_l(x)) |l| {
        const prefix = encode_l(x, l);
        if (l == 0) {
            // If `l` is 0, the value is stored in the prefix to save space during encoding.
            return EncodingResult.build(prefix, &[_]u8{});
        } else {
            // In this case, we need to store the length and pack the value
            // of the remainder at the end.
            const data = encodeFixedLengthInteger(x);
            return EncodingResult.build(prefix, &data);
        }
    } else {
        // When `l` is not found, we need to encode the value as a fixed-length integer.
        const data = encodeFixedLengthInteger(x);
        return EncodingResult.build(0xFF, &data);
    }
}

// Tests
comptime {
    _ = @import("codec/tests.zig");
}
