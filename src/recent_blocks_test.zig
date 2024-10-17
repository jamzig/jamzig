const std = @import("std");
const testing = std.testing;
const RecentHistory = @import("recent_blocks.zig").RecentHistory;
const RecentBlock = @import("recent_blocks.zig").RecentBlock;
const Hash = @import("recent_blocks.zig").Hash;
const HistoryTestVector = @import("tests/vectors/libs/history.zig").HistoryTestVector;
const TestCase = @import("tests/vectors/libs/history.zig").TestCase;

fn compareBlocks(expected: RecentBlock, actual: RecentBlock) !void {
    try testing.expectEqualSlices(u8, &expected.header_hash, &actual.header_hash);
    try testing.expectEqualSlices(u8, &expected.state_root, &actual.state_root);
    try testing.expectEqualSlices(Hash, expected.beefy_mmr, actual.beefy_mmr);
    try testing.expectEqualSlices(Hash, expected.work_report_hashes, actual.work_report_hashes);
}

test "recent blocks: parsing all test cases" {
    const allocator = testing.allocator;
    const target_dir = "src/tests/vectors/history/history/data";

    var dir = try std.fs.cwd().openDir(target_dir, .{ .iterate = true });
    defer dir.close();

    var dir_iterator = dir.iterate();
    while (try dir_iterator.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".json")) continue;

        const file_path = try std.fs.path.join(allocator, &[_][]const u8{ target_dir, entry.name });
        defer allocator.free(file_path);

        const vector = try HistoryTestVector(TestCase).build_from(allocator, file_path);
        defer vector.deinit();

        // Test the RecentHistory implementation
        var recent_history = try RecentHistory.init(allocator, 341);
        defer recent_history.deinit();

        // Set up pre-state
        for (vector.expected.value.pre_state.beta) |block_info| {
            var block = RecentBlock{
                .header_hash = block_info.header_hash.bytes,
                .state_root = block_info.state_root.bytes,
                .beefy_mmr = try allocator.alloc(Hash, block_info.mmr.peaks.len),
                .work_report_hashes = try allocator.alloc(Hash, block_info.reported.len),
            };
            for (block_info.mmr.peaks, 0..) |peak, i| {
                if (peak) |p| {
                    block.beefy_mmr[i] = p.bytes;
                } else {
                    @memset(&block.beefy_mmr[i], 0);
                }
            }
            for (block_info.reported, 0..) |report, i| {
                block.work_report_hashes[i] = report.bytes;
            }
            try recent_history.addBlock(block);
        }

        // Process the new block
        const new_block = RecentBlock{
            .header_hash = vector.expected.value.input.header_hash.bytes,
            .state_root = vector.expected.value.input.parent_state_root.bytes,
            .beefy_mmr = try allocator.alloc(Hash, 1),
            .work_report_hashes = try allocator.alloc(Hash, vector.expected.value.input.work_packages.len),
        };
        new_block.beefy_mmr[0] = vector.expected.value.input.accumulate_root.bytes;
        for (vector.expected.value.input.work_packages, 0..) |work_package, i| {
            new_block.work_report_hashes[i] = work_package.bytes;
        }
        try recent_history.addBlock(new_block);

        // Verify the post-state
        try testing.expectEqual(vector.expected.value.post_state.beta.len, recent_history.blocks.items.len);
        for (vector.expected.value.post_state.beta, 0..) |expected_block, i| {
            const actual_block = recent_history.getBlock(i).?;
            const expected_recent_block = RecentBlock{
                .header_hash = expected_block.header_hash.bytes,
                .state_root = expected_block.state_root.bytes,
                .beefy_mmr = try allocator.alloc(Hash, expected_block.mmr.peaks.len),
                .work_report_hashes = try allocator.alloc(Hash, expected_block.reported.len),
            };
            for (expected_block.mmr.peaks, 0..) |peak, j| {
                if (peak) |p| {
                    expected_recent_block.beefy_mmr[j] = p.bytes;
                } else {
                    @memset(&expected_recent_block.beefy_mmr[j], 0);
                }
            }
            for (expected_block.reported, 0..) |report, j| {
                expected_recent_block.work_report_hashes[j] = report.bytes;
            }
            try compareBlocks(expected_recent_block, actual_block);
            allocator.free(expected_recent_block.beefy_mmr);
            allocator.free(expected_recent_block.work_report_hashes);
        }
    }
}
