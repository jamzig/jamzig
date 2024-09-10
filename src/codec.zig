const std = @import("std");

pub fn deserialize(comptime T: type, data: []u8) !T {
    _ = data;
    return error.NotImplemented;
}

// TODO: look into optimizing this

// (271) Function to encode an integer into a specified number of octets in
// little-endian format
fn encodeFixedLengthInteger(comptime L: usize, x: u64, allocator: std.mem.Allocator) ![]u8 {
    if (L == 0) {
        return allocator.alloc(u8, 0);
    } else {
        const lower_byte = x & 0xff;
        const rest_encoded = try encodeFixedLengthInteger(L - 1, x >> 8, allocator);
        defer allocator.free(rest_encoded);
        const result = try allocator.alloc(u8, 1 + rest_encoded.len);
        result[0] = @intCast(lower_byte);
        std.mem.copyForwards(u8, result[1..], rest_encoded);
        return result;
    }
}

test "codec: encodeFixedLengthInteger" {
    const allocator = std.testing.allocator;
    const encoded = try encodeFixedLengthInteger(3, 0x123456, allocator);
    defer allocator.free(encoded);
    const expected: [3]u8 = [_]u8{
        0x56, 0x34, 0x12,
    };
    try std.testing.expectEqualSlices(u8, &expected, encoded);
}

/// (272) Function to encode an integer (0 to 2^64 - 1) into a variable-length
/// sequence (1 to 9 bytes)
fn encodeGeneralInteger(x: u64, allocator: *std.mem.Allocator) ![]u8 {
    if (x == 0) {
        return allocator.alloc(u8, 1); // return [0] as the encoded value
    }

    var l: u8 = 1;
    while ((x >> (7 * l)) != 0 and l < 9) : (l += 1) {}

    if (l == 9) {
        return try encodeFixedLengthInteger(8, x, allocator); // special case for 64-bit integers
    } else {
        const prefix = 0x80 - l;
        const encoded_value = try encodeFixedLengthInteger(l, x, allocator);
        const result = try allocator.alloc(u8, 1 + encoded_value.len);
        result[0] = @intCast(prefix);
        std.mem.copy(u8, result[1..], encoded_value);
        return result;
    }
}
