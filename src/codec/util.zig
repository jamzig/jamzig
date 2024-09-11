const std = @import("std");

// bounds l=0: 1 <= x < 128
// bounds l=1: 128 <= x < 16384
// bounds l=2: 16384 <= x < 2097152
// bounds l=3: 2097152 <= x < 268435456
// bounds l=4: 268435456 <= x < 34359738368
// bounds l=5: 34359738368 <= x < 4398046511104
// bounds l=6: 4398046511104 <= x < 562949953421312
// bounds l=7: 562949953421312 <= x < 72057594037927936
pub fn find_l(x: anytype) ?u8 {
    // Iterate over l in the range of 0 to 7 (l in N_8)
    var l: u8 = 0;
    while (l < 8) : (l += 1) {
        const lower_bound: u64 = @as(u64, 1) << @intCast(7 * l); // 2^(7l)
        const upper_bound: u64 = @as(u64, 1) << @intCast(7 * (l + 1)); // 2^(7(l+1))

        // Check if x falls within the range [2^(7l), 2^(7(l+1)))
        if (x >= lower_bound and x < upper_bound) {
            return l; // l is found
        }
    }

    // If no valid l is found, return null (meaning x is too large for this range)
    return null;
}

pub fn encode_l(x: anytype, l: u8) u8 {
    const prefix: u8 = @intCast((@as(u16, 1) << 8) - (@as(u16, 1) << @intCast(8 - l)));

    // when l=0, x will be between 1 and 127 inclusive, so safe to add x to0x80
    if (l == 0) {
        return prefix + @as(u8, @intCast(x & 0xFF));
    }

    // First byte is the computed prefix
    return prefix;
}
