const std = @import("std");

/// Sign extends any integer type (signed or unsigned) to u64.
/// Takes advantage of comptime type checking to ensure we only work with integers.
pub fn signExtendToU64(comptime T: type, value: T) u64 {
    // First, verify at compile time that we're working with an integer
    comptime {
        if (!(@typeInfo(T) == .int)) {
            @compileError("Input type must be an integer");
        }
    }

    // Get information about our input type at compile time
    const type_info = @typeInfo(T).int;
    const bits = type_info.bits;

    // No need to sign extend if we're already 64 bits
    if (bits == 64) {
        // If it's already i64, we just need to bitcast to u64
        if (type_info.signedness == .signed) {
            return @as(u64, @bitCast(value));
        }
        // If it's already u64, we can return directly
        return value;
    }

    // For smaller types, we need to do proper sign extension
    if (type_info.signedness == .signed) {
        // For signed types, we can directly cast to i64 then to u64
        const extended = @as(i64, @intCast(value));
        return @bitCast(extended);
    } else {
        // For unsigned types, we need to go through the signed variant first
        const SignedT = std.meta.Int(.signed, bits);
        const signed = @as(SignedT, @bitCast(value));
        const extended = @as(i64, @intCast(signed));
        return @bitCast(extended);
    }
}

test "signExtendToU64" {
    const testing = std.testing;

    // Test with unsigned types
    try testing.expectEqual(@as(u64, 0xFFFFFFFFFFFFFFFF), signExtendToU64(u8, 0xFF)); // -1 as u8
    try testing.expectEqual(@as(u64, 0x0000000000000042), signExtendToU64(u8, 0x42)); // +66 as u8
    try testing.expectEqual(@as(u64, 0xFFFFFFFFFFFFFFFF), signExtendToU64(u32, 0xFFFFFFFF)); // -1 as u32

    // Test with signed types
    try testing.expectEqual(@as(u64, 0xFFFFFFFFFFFFFFFF), signExtendToU64(i8, -1));
    try testing.expectEqual(@as(u64, 0x0000000000000042), signExtendToU64(i8, 66));
    try testing.expectEqual(@as(u64, 0xFFFFFFFFFFFFFFFF), signExtendToU64(i32, -1));

    // Test with 64-bit types
    try testing.expectEqual(@as(u64, 0xFFFFFFFFFFFFFFFF), signExtendToU64(i64, -1));
    try testing.expectEqual(@as(u64, 0xFFFFFFFFFFFFFFFF), signExtendToU64(u64, 0xFFFFFFFFFFFFFFFF));
}
