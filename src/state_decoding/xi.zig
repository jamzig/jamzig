const std = @import("std");

const types = @import("../types.zig");

const sort = std.sort;
const decoder = @import("../codec/decoder.zig");
const state = @import("../state.zig");

const GlobalIndex = std.AutoHashMapUnmanaged(types.WorkPackageHash, void);

pub fn decode(comptime epoch_size: usize, allocator: std.mem.Allocator, reader: anytype) !state.Xi(epoch_size) {
    var global_index: GlobalIndex = .{};
    var result: [epoch_size]std.AutoHashMapUnmanaged([32]u8, void) = undefined;
    for (&result) |*epoch| {
        epoch.* = try decodeTimeslotEntryAndFillGlobalIndex(allocator, reader, &global_index);
    }
    return .{ .entries = result, .allocator = allocator, .global_index = global_index };
}

pub fn decodeTimeslotEntryAndFillGlobalIndex(allocator: std.mem.Allocator, reader: anytype, global_index: *GlobalIndex) !std.AutoHashMapUnmanaged([32]u8, void) {
    var result = std.AutoHashMapUnmanaged([32]u8, void){};
    errdefer result.deinit(allocator);

    // Read length prefix
    var length_buf: [1]u8 = undefined;
    _ = try reader.readAll(&length_buf);
    const count = length_buf[0];

    // Read each key-value pair
    var i: usize = 0;
    while (i < count) : (i += 1) {
        var key: [32]u8 = undefined;
        // var value: [32]u8 = undefined;

        _ = try reader.readAll(&key);
        // _ = try reader.readAll(&value);

        try result.put(allocator, key, {});
        try global_index.put(allocator, key, {});
    }

    return result;
}
