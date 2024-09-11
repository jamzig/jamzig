const std = @import("std");
const codec = @import("../codec.zig");
const codec_utils = @import("util.zig");

// encodeFixedLengthInteger tests

const encodeFixedLengthInteger = codec.encodeFixedLengthInteger;

test "codec: encodeFixedLengthInteger - u8 (edge case: 0)" {
    const encoded8: [1]u8 = encodeFixedLengthInteger(@as(u8, 0));
    const expected8: [1]u8 = [_]u8{0x00};
    try std.testing.expectEqualSlices(u8, &expected8, &encoded8);
}

test "codec: encodeFixedLengthInteger - u16 (max value)" {
    const encoded16: [2]u8 = encodeFixedLengthInteger(@as(u16, 0xFFFF));
    const expected16: [2]u8 = [_]u8{ 0xFF, 0xFF };
    try std.testing.expectEqualSlices(u8, &expected16, &encoded16);
}
test "codec: encodeFixedLengthInteger - u24" {
    const encoded24: [4]u8 = encodeFixedLengthInteger(@as(u24, 0x123456));
    const expected24: [4]u8 = [_]u8{ 0x56, 0x34, 0x12, 0x00 };
    try std.testing.expectEqualSlices(u8, &expected24, &encoded24);
}

test "codec: encodeFixedLengthInteger - u32" {
    const encoded32: [4]u8 = encodeFixedLengthInteger(@as(u32, 0x12345678));
    const expected32: [4]u8 = [_]u8{ 0x78, 0x56, 0x34, 0x12 };
    try std.testing.expectEqualSlices(u8, &expected32, &encoded32);
}

test "codec: encodeFixedLengthInteger - u64" {
    const encoded64: [8]u8 = encodeFixedLengthInteger(@as(u64, 0x123456789ABCDEF0));
    const expected64: [8]u8 = [_]u8{ 0xF0, 0xDE, 0xBC, 0x9A, 0x78, 0x56, 0x34, 0x12 };
    try std.testing.expectEqualSlices(u8, &expected64, &encoded64);
}

test "codec: encodeFixedLengthInteger - u128" {
    const encoded128: [16]u8 = encodeFixedLengthInteger(@as(u128, 0x123456789ABCDEF0123456789ABCDEF0));
    const expected128: [16]u8 = [_]u8{ 0xF0, 0xDE, 0xBC, 0x9A, 0x78, 0x56, 0x34, 0x12, 0xF0, 0xDE, 0xBC, 0x9A, 0x78, 0x56, 0x34, 0x12 };
    try std.testing.expectEqualSlices(u8, &expected128, &encoded128);
}

// find_l tests

const find_l = codec_utils.find_l;

test "codec: find_l - u8 values" {
    // lower bound for u8 will be 1
    // upper bound for u8 will be 128
    try std.testing.expectEqual(@as(?u8, null), find_l(@as(u8, 0)));
    for (1..128) |i| {
        try std.testing.expectEqual(@as(?u8, 0), find_l(@as(u8, @intCast(i))));
    }
    for (128..256) |i| {
        try std.testing.expectEqual(@as(?u8, 1), find_l(@as(u8, @intCast(i))));
    }
}

test "codec: find_l - u16 values" {
    // lower bound for u8 will be 1
    // upper bound for u8 will be 128
    try std.testing.expectEqual(@as(?u8, null), find_l(@as(u16, 0)));

    try std.testing.expectEqual(@as(?u8, 0), find_l(@as(u16, 127)));
    try std.testing.expectEqual(@as(?u8, 1), find_l(@as(u16, 128)));

    try std.testing.expectEqual(@as(?u8, 1), find_l(@as(u16, 256)));
    try std.testing.expectEqual(@as(?u8, 1), find_l(@as(u16, 16383)));
    try std.testing.expectEqual(@as(?u8, 2), find_l(@as(u16, 16384)));
}

test "codec: find_l - u32 values" {
    try std.testing.expectEqual(@as(?u8, 2), find_l(@as(u32, 65536)));
    try std.testing.expectEqual(@as(?u8, 3), find_l(@as(u32, 2097152)));
    try std.testing.expectEqual(@as(?u8, 4), find_l(@as(u32, 268435456)));
}

test "codec: find_l - u64 values" {
    try std.testing.expectEqual(@as(?u8, 4), find_l(@as(u64, 4294967296)));
    try std.testing.expectEqual(@as(?u8, 5), find_l(@as(u64, 34359738368)));

    try std.testing.expectEqual(@as(?u8, 5), find_l(@as(u64, 4398046511103)));
    try std.testing.expectEqual(@as(?u8, 6), find_l(@as(u64, 4398046511104)));

    try std.testing.expectEqual(@as(?u8, 6), find_l(@as(u64, 562949953421311)));
    try std.testing.expectEqual(@as(?u8, 7), find_l(@as(u64, 562949953421312)));

    try std.testing.expectEqual(@as(?u8, 7), find_l(@as(u64, 72057594037927935)));
    try std.testing.expectEqual(@as(?u8, null), find_l(@as(u64, 72057594037927936)));

    try std.testing.expectEqual(@as(?u8, null), find_l(@as(u64, std.math.maxInt(u64))));
}

// encodeInteger tests

const encodeInteger = codec.encodeInteger;

test "codec: encodeInteger - u8 (0)" {
    const result = encodeInteger(@as(u8, 0));
    try std.testing.expectEqual(@as(u8, 1), result.len);
    try std.testing.expectEqualSlices(u8, &[_]u8{0x00}, result.as_slice());
}

test "codec: encodeInteger - u8 (10)" {
    const result = encodeInteger(@as(u8, 10));
    try std.testing.expectEqual(@as(u8, 1), result.len);
}

test "codec: encodeInteger - u8 (127)" {
    const result = encodeInteger(@as(u8, 127));
    try std.testing.expectEqual(@as(u8, 1), result.len);
    try std.testing.expectEqualSlices(u8, &[_]u8{0x7F}, result.data[0..1]);
}

test "codec: encodeInteger - u8 (128)" {
    const result = encodeInteger(@as(u8, 128));
    try std.testing.expectEqual(@as(u8, 2), result.len);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x81, 0x80 }, result.data[0..2]);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x81, 0x80 }, result.as_slice());
}

test "codec: encodeInteger - fuzz test" {
    const TestCase = struct {
        value: u64,
        bit_width: u8,
    };

    var random = std.Random.DefaultPrng.init(0);
    const prng = random.random();

    const bit_widths = [_]u8{ 8, 16, 32, 64 };

    for (0..1_000_000) |_| {
        const test_case = TestCase{
            .value = prng.int(u64),
            .bit_width = bit_widths[prng.intRangeAtMost(usize, 0, 3)],
        };

        const encoded = switch (test_case.bit_width) {
            8 => encodeInteger(@as(u8, @intCast(test_case.value % std.math.maxInt(u8)))),
            16 => encodeInteger(@as(u16, @intCast(test_case.value % std.math.maxInt(u16)))),
            32 => encodeInteger(@as(u32, @intCast(test_case.value % std.math.maxInt(u32)))),
            64 => encodeInteger(@as(u64, test_case.value % std.math.maxInt(u64))),
            else => unreachable,
        };

        // Verify that the encoded result is not empty
        try std.testing.expect(encoded.len > 0);

        // Verify that the encoded result is not longer than 9 bytes
        try std.testing.expect(encoded.len <= 9);

        // TODO: Add decoding function and verify that decoding the result gives back the original value
    }
}
