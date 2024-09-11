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
    const base_value = @as(u16, 1) << @intCast(8 - l); // 2^(8-l)
    const prefix = (@as(u16, 1) << @intCast(8)) - base_value + (x >> @min(8 * l, @bitSizeOf(@TypeOf(x)) - 1));

    // First byte is the computed prefix
    return @intCast(prefix);
}
