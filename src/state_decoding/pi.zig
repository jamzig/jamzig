const std = @import("std");
const testing = std.testing;
const validator_statistics = @import("../validator_stats.zig");
const Pi = validator_statistics.Pi;
const ValidatorStats = validator_statistics.ValidatorStats;
const ValidatorIndex = @import("../types.zig").ValidatorIndex;

pub fn decode(validators_count: u32, reader: anytype, allocator: std.mem.Allocator) !Pi {
    // Initialize Pi with validator count which we'll determine from the data
    var current_epoch_stats = try std.ArrayList(ValidatorStats).initCapacity(allocator, validators_count);
    errdefer current_epoch_stats.deinit();

    var previous_epoch_stats = try std.ArrayList(ValidatorStats).initCapacity(allocator, validators_count);
    errdefer previous_epoch_stats.deinit();

    // Read current epoch stats
    try decodeEpochStats(validators_count, reader, &current_epoch_stats);

    // Read previous epoch stats
    try decodeEpochStats(validators_count, reader, &previous_epoch_stats);

    // Ensure both arrays have same length
    if (current_epoch_stats.items.len != previous_epoch_stats.items.len) {
        return error.InvalidData;
    }

    return Pi{
        .current_epoch_stats = current_epoch_stats,
        .previous_epoch_stats = previous_epoch_stats,
        .allocator = allocator,
        .validator_count = current_epoch_stats.items.len,
    };
}

fn decodeEpochStats(validators_count: u32, reader: anytype, stats: *std.ArrayList(ValidatorStats)) !void {
    for (0..validators_count) |_| {
        // Try to read all stats fields
        const blocks_produced = try reader.readInt(u32, .little);
        const tickets_introduced = try reader.readInt(u32, .little);
        const preimages_introduced = try reader.readInt(u32, .little);
        const octets_across_preimages = try reader.readInt(u32, .little);
        const reports_guaranteed = try reader.readInt(u32, .little);
        const availability_assurances = try reader.readInt(u32, .little);

        try stats.append(ValidatorStats{
            .blocks_produced = blocks_produced,
            .tickets_introduced = tickets_introduced,
            .preimages_introduced = preimages_introduced,
            .octets_across_preimages = octets_across_preimages,
            .reports_guaranteed = reports_guaranteed,
            .availability_assurances = availability_assurances,
        });
    }
}

test "decode Pi - successful case" {
    // Create a test buffer with mock data
    var buffer: [4 * @sizeOf(ValidatorStats)]u8 = undefined; // Space for 2 validators × 2 epochs
    var fbs = std.io.fixedBufferStream(&buffer);
    var writer = fbs.writer();

    // Write current epoch data for 2 validators
    try writer.writeInt(u32, 1, .little); // blocks_produced
    try writer.writeInt(u32, 2, .little); // tickets_introduced
    try writer.writeInt(u32, 3, .little); // preimages_introduced
    try writer.writeInt(u32, 4, .little); // octets_across_preimages
    try writer.writeInt(u32, 5, .little); // reports_guaranteed
    try writer.writeInt(u32, 6, .little); // availability_assurances

    try writer.writeInt(u32, 7, .little);
    try writer.writeInt(u32, 8, .little);
    try writer.writeInt(u32, 9, .little);
    try writer.writeInt(u32, 10, .little);
    try writer.writeInt(u32, 11, .little);
    try writer.writeInt(u32, 12, .little);

    // Write previous epoch data
    try writer.writeInt(u32, 13, .little);
    try writer.writeInt(u32, 14, .little);
    try writer.writeInt(u32, 15, .little);
    try writer.writeInt(u32, 16, .little);
    try writer.writeInt(u32, 17, .little);
    try writer.writeInt(u32, 18, .little);

    try writer.writeInt(u32, 19, .little);
    try writer.writeInt(u32, 20, .little);
    try writer.writeInt(u32, 21, .little);
    try writer.writeInt(u32, 22, .little);
    try writer.writeInt(u32, 23, .little);
    try writer.writeInt(u32, 24, .little);

    // Reset reader position
    fbs.reset();
    const reader = fbs.reader();

    // Decode the data
    var pi = try decode(2, reader, testing.allocator);
    defer pi.deinit();

    // Verify current epoch stats
    try testing.expectEqual(@as(usize, 2), pi.current_epoch_stats.items.len);
    try testing.expectEqual(@as(u32, 1), pi.current_epoch_stats.items[0].blocks_produced);
    try testing.expectEqual(@as(u32, 2), pi.current_epoch_stats.items[0].tickets_introduced);
    try testing.expectEqual(@as(u32, 7), pi.current_epoch_stats.items[1].blocks_produced);
    try testing.expectEqual(@as(u32, 8), pi.current_epoch_stats.items[1].tickets_introduced);

    // Verify previous epoch stats
    try testing.expectEqual(@as(usize, 2), pi.previous_epoch_stats.items.len);
    try testing.expectEqual(@as(u32, 13), pi.previous_epoch_stats.items[0].blocks_produced);
    try testing.expectEqual(@as(u32, 14), pi.previous_epoch_stats.items[0].tickets_introduced);
    try testing.expectEqual(@as(u32, 19), pi.previous_epoch_stats.items[1].blocks_produced);
    try testing.expectEqual(@as(u32, 20), pi.previous_epoch_stats.items[1].tickets_introduced);
}

test "decode Pi - empty buffer" {
    var buffer: [0]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const reader = fbs.reader();

    // Attempt to decode empty buffer should result in error
    try testing.expectError(error.EndOfStream, decode(1, reader, testing.allocator));
}

test "decode Pi - incomplete data" {
    var buffer: [20]u8 = undefined; // Not enough data for complete stats
    var fbs = std.io.fixedBufferStream(&buffer);
    var writer = fbs.writer();

    // Write partial data
    try writer.writeInt(u32, 1, .little);
    try writer.writeInt(u32, 2, .little);
    try writer.writeInt(u32, 3, .little);
    try writer.writeInt(u32, 4, .little);
    try writer.writeInt(u32, 5, .little);

    fbs.reset();
    const reader = fbs.reader();

    // Attempt to decode incomplete data should result in error
    try testing.expectError(error.EndOfStream, decode(1, reader, testing.allocator));
}
